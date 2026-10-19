use bytes::Bytes;
use cpal::{traits::{DeviceTrait, HostTrait, StreamTrait}, FromSample, SampleFormat, SizedSample, Stream, StreamConfig};
use opus::{Application, Channels, Decoder, Encoder};
use serde_json::{json, Value};
use std::{collections::VecDeque, sync::{atomic::{AtomicBool, Ordering}, Arc, Mutex}, thread, time::{Duration, Instant}};
use tokio::sync::mpsc;
use webrtc::{
    api::{media_engine::{MediaEngine, MIME_TYPE_OPUS}, APIBuilder},
    ice_transport::ice_connection_state::RTCIceConnectionState,
    media::Sample as MediaSample,
    peer_connection::{configuration::RTCConfiguration, sdp::session_description::RTCSessionDescription, RTCPeerConnection},
    rtp_transceiver::rtp_codec::RTCRtpCodecCapability,
    track::{track_local::{track_local_static_sample::TrackLocalStaticSample, TrackLocal}, track_remote::TrackRemote},
};

const RATE: u32 = 48_000;
const FRAME: usize = 960;

#[derive(Debug)]
pub enum Command {
    Start { thread_id: String, anchor: Option<String> },
    End,
    Mute(bool),
    SpeakerMute(bool),
}

pub fn start_worker(base: String, token: Option<String>, ui: std::sync::mpsc::Sender<(String, Result<Value, String>)>) -> mpsc::UnboundedSender<Command> {
    let (tx, rx) = mpsc::unbounded_channel();
    thread::spawn(move || {
        let runtime = tokio::runtime::Builder::new_multi_thread().enable_all().build();
        match runtime {
            Ok(runtime) => runtime.block_on(worker(base, token, ui, rx)),
            Err(error) => { let _ = ui.send(("voice".into(), Ok(json!({"status":"idle","error":format!("Voice runtime could not start: {error}")})))); }
        }
    });
    tx
}

async fn worker(base: String, token: Option<String>, ui: std::sync::mpsc::Sender<(String, Result<Value, String>)>, mut commands: mpsc::UnboundedReceiver<Command>) {
    while let Some(command) = commands.recv().await {
        let Command::Start { thread_id, anchor } = command else { continue };
        send_ui(&ui, "connecting", None, "listening", "", "", 0, false, false);
        match connect(&base, token.as_deref(), &thread_id).await {
            Ok(call) => run_call(&base, token.as_deref(), &ui, &mut commands, call, anchor).await,
            Err(error) => send_ui(&ui, "idle", Some(&error), "listening", "", "", 0, false, false),
        }
    }
}

struct AudioInput { _stream: Stream, receiver: mpsc::Receiver<Vec<i16>> }

struct AudioOutput { _stream: Stream, samples: Arc<Mutex<VecDeque<f32>>>, muted: Arc<AtomicBool> }

struct VoiceCall {
    id: String,
    peer: Arc<RTCPeerConnection>,
    data_channel: Arc<webrtc::data_channel::RTCDataChannel>,
    track: Arc<TrackLocalStaticSample>,
    input: AudioInput,
    _output: AudioOutput,
    mic_muted: Arc<AtomicBool>,
    started: Instant,
    transcript: Vec<String>,
    anchor: Option<String>,
    ice_rx: mpsc::UnboundedReceiver<RTCIceConnectionState>,
    messages_rx: mpsc::UnboundedReceiver<String>,
}

async fn connect(base: &str, token: Option<&str>, thread_id: &str) -> Result<VoiceCall, String> {
    let input = open_input()?;
    let output = open_output()?;
    let mut media = MediaEngine::default();
    media.register_default_codecs().map_err(|error| format!("WebRTC audio setup failed: {error}"))?;
    let peer = Arc::new(APIBuilder::new().with_media_engine(media).build().new_peer_connection(RTCConfiguration::default()).await.map_err(|error| format!("WebRTC peer could not start: {error}"))?);
    let track = Arc::new(TrackLocalStaticSample::new(RTCRtpCodecCapability { mime_type: MIME_TYPE_OPUS.to_owned(), clock_rate: RATE, channels: 2, ..Default::default() }, "aether-mic".into(), "aether-audio".into()));
    let local_track: Arc<dyn TrackLocal + Send + Sync> = track.clone();
    peer.add_track(local_track).await.map_err(|error| format!("Microphone track could not be added: {error}"))?;

    let (ice_tx, ice_rx) = mpsc::unbounded_channel();
    peer.on_ice_connection_state_change(Box::new(move |state| { let _ = ice_tx.send(state); Box::pin(async {}) }));
    let (messages_tx, messages_rx) = mpsc::unbounded_channel();
    let data_channel = peer.create_data_channel("oai-events", None).await.map_err(|error| format!("Voice event channel could not be created: {error}"))?;
    data_channel.on_message(Box::new(move |message| { let _ = messages_tx.send(String::from_utf8_lossy(&message.data).into_owned()); Box::pin(async {}) }));

    let samples = Arc::clone(&output.samples);
    peer.on_track(Box::new(move |remote: Arc<TrackRemote>, _, _| {
        let samples = Arc::clone(&samples);
        tokio::spawn(async move { play_remote_audio(remote, samples).await; });
        Box::pin(async {})
    }));

    let offer = peer.create_offer(None).await.map_err(|error| format!("Voice offer could not be created: {error}"))?;
    let mut gathered = peer.gathering_complete_promise().await;
    peer.set_local_description(offer).await.map_err(|error| format!("Voice offer could not be set: {error}"))?;
    tokio::time::timeout(Duration::from_secs(25), gathered.recv()).await.map_err(|_| "Network setup timed out while gathering voice connection details.".to_owned())?;
    let local = peer.local_description().await.ok_or_else(|| "Voice offer is missing.".to_owned())?;
    let client = reqwest::Client::new();
    let response = api(&client, base, token, "POST", "/voice/calls", Some(json!({"threadId":thread_id,"sdp":local.sdp}))).await?;
    let id = response["id"].as_str().ok_or_else(|| "Voice server returned no call ID.".to_owned())?.to_owned();
    let sdp = response["sdp"].as_str().ok_or_else(|| "Voice server returned no audio answer.".to_owned())?;
    let answer = RTCSessionDescription::answer(sdp.to_owned()).map_err(|error| format!("Voice answer was invalid: {error}"))?;
    peer.set_remote_description(answer).await.map_err(|error| format!("Voice answer could not be applied: {error}"))?;
    let _ = input._stream.play();
    let _ = output._stream.play();
    Ok(VoiceCall { id, peer, data_channel, track, input, _output: output, mic_muted: Arc::new(AtomicBool::new(false)), started: Instant::now(), transcript: Vec::new(), anchor: None, ice_rx, messages_rx })
}

async fn run_call(base: &str, token: Option<&str>, ui: &std::sync::mpsc::Sender<(String, Result<Value, String>)>, commands: &mut mpsc::UnboundedReceiver<Command>, mut call: VoiceCall, anchor: Option<String>) {
    call.anchor = anchor;
    let (audio_tx, mut audio_rx) = mpsc::channel::<Vec<i16>>(8);
    let (receiver_sentinel, placeholder) = mpsc::channel(1);
    let mut input_receiver = std::mem::replace(&mut call.input.receiver, placeholder);
    drop(receiver_sentinel);
    let forwarding = Arc::new(tokio::sync::Mutex::new(()));
    let sender = audio_tx.clone();
    let reader = tokio::spawn(async move { while let Some(frame) = input_receiver.recv().await { if sender.send(frame).await.is_err() { break; } } });
    let client = reqwest::Client::new();
    let mut encoder = match Encoder::new(RATE, Channels::Mono, Application::Voip) {
        Ok(encoder) => encoder,
        Err(error) => { finish(base, token, &client, &call).await; send_ui(ui,"idle",Some(&format!("Audio encoder could not start: {error}")),"listening","","",0,false,false); return; }
    };
    let mut packet = vec![0u8; 4000];
    let mut poll = tokio::time::interval(Duration::from_secs(2));
    let started = Instant::now();
    let mut transcript = Vec::<String>::new();
    let mut caption = String::new();
    let mut user_caption = String::new();
    let mut phase = "listening".to_owned();
    let mut failures = 0;
    let mut connected = false;
    let mut disconnected_at: Option<Instant> = None;
    let muted = Arc::clone(&call.mic_muted);
    let speaker_muted = Arc::clone(&call._output.muted);
    let mut end_error: Option<String> = None;

    send_ui(ui,"connecting",None,&phase,"","",0,false,false);
    loop {
        tokio::select! {
            command = commands.recv() => match command {
                Some(Command::End) | None => break,
                Some(Command::Mute(value)) => { muted.store(value, Ordering::Relaxed); send_ui(ui, if connected{"active"}else{"connecting"},None,&phase,&caption,&user_caption,started.elapsed().as_secs() as u64,value,speaker_muted.load(Ordering::Relaxed)); },
                Some(Command::SpeakerMute(value)) => { speaker_muted.store(value, Ordering::Relaxed); send_ui(ui, if connected{"active"}else{"connecting"},None,&phase,&caption,&user_caption,started.elapsed().as_secs() as u64,muted.load(Ordering::Relaxed),value); },
                Some(Command::Start { .. }) => {},
            },
            frame = audio_rx.recv() => if let Some(frame) = frame {
                if muted.load(Ordering::Relaxed) { continue; }
                if let Ok(size) = encoder.encode(&frame, &mut packet) {
                    let _guard = forwarding.lock().await;
                    let _ = call.track.write_sample(&MediaSample { data: Bytes::copy_from_slice(&packet[..size]), duration: Duration::from_millis(20), ..Default::default() }).await;
                }
            },
            state = call.ice_rx.recv() => if let Some(state) = state {
                match state {
                    RTCIceConnectionState::Connected | RTCIceConnectionState::Completed => {
                        disconnected_at = None;
                        if !connected { connected = true; let _ = api(&client,base,token,"POST",&format!("/voice/calls/{}/active",call.id),Some(json!({}))).await; }
                        send_ui(ui,"active",None,&phase,&caption,&user_caption,started.elapsed().as_secs() as u64,muted.load(Ordering::Relaxed),speaker_muted.load(Ordering::Relaxed));
                    }
                    RTCIceConnectionState::Disconnected => { disconnected_at = Some(Instant::now()); }
                    RTCIceConnectionState::Failed | RTCIceConnectionState::Closed => { end_error = Some("The voice connection dropped.".into()); break; }
                    _ => {}
                }
            },
            message = call.messages_rx.recv() => if let Some(message) = message {
                if let Ok(event) = serde_json::from_str::<Value>(&message) {
                    match event["type"].as_str().unwrap_or("") {
                        "input_audio_buffer.speech_started" => { phase = "listening".into(); caption.clear(); }
                        "response.created" => { phase = "thinking".into(); caption.clear(); }
                        "output_audio_buffer.stopped" => phase = "listening".into(),
                        "response.output_audio_transcript.delta" => { phase = "speaking".into(); caption.push_str(event["delta"].as_str().unwrap_or("")); }
                        "conversation.item.input_audio_transcription.completed" => if let Some(text) = event["transcript"].as_str() { user_caption = text.to_owned(); transcript.push(format!("You: {text}")); },
                        "response.output_audio_transcript.done" => if let Some(text) = event["transcript"].as_str() { transcript.push(format!("Dot: {text}")); },
                        "error" => end_error = Some("The voice provider reported a session error. End the call and retry.".into()),
                        "response.function_call_arguments.done" => {
                            if event["name"].as_str() == Some("ask_compute") {
                                let tool_id = event["call_id"].as_str().unwrap_or("");
                                let args = event["arguments"].as_str().and_then(|value|serde_json::from_str::<Value>(value).ok()).unwrap_or(Value::Null);
                                if !tool_id.is_empty() {
                                    phase = "thinking".into();
                                    let request = args["request"].as_str().unwrap_or("");
                                    let context = transcript.join("\n");
                                    let result = api(&client,base,token,"POST",&format!("/voice/calls/{}/compute",call.id),Some(json!({"toolCallId":tool_id,"request":request,"transcript":context.chars().rev().take(12000).collect::<String>().chars().rev().collect::<String>()}))).await;
                                    let text = result.ok().and_then(|value|value["text"].as_str().map(str::to_owned)).unwrap_or_else(||"Compute failed. Please try again.".into());
                                    let reply = json!({"type":"conversation.item.create","item":{"type":"function_call_output","call_id":tool_id,"output":text}}).to_string();
                                    let _ = call.data_channel.send(&Bytes::from(reply)).await;
                                    let _ = call.data_channel.send(&Bytes::from(r#"{"type":"response.create"}"#.to_owned())).await;
                                }
                            }
                        }
                        _ => {}
                    }
                    send_ui(ui,if connected{"active"}else{"connecting"},None,&phase,&caption,&user_caption,started.elapsed().as_secs() as u64,muted.load(Ordering::Relaxed),speaker_muted.load(Ordering::Relaxed));
                }
            },
            _ = poll.tick() => {
                if started.elapsed() >= Duration::from_secs(900) { end_error=Some("Voice call ended after 15 minutes.".into()); break; }
                if disconnected_at.is_some_and(|at|at.elapsed()>=Duration::from_secs(5)) { end_error=Some("The voice connection dropped.".into()); break; }
                match api(&client,base,token,"GET",&format!("/voice/calls/{}",call.id),None).await {
                    Ok(value) => { failures=0; if !value["endedAt"].is_null() { break; } }
                    Err(_) => { failures+=1; if failures>=3 { end_error=Some("Call control connection was lost.".into()); break; } }
                }
            }
        }
        if end_error.is_some() { break; }
    }
    call.transcript = transcript;
    reader.abort();
    finish(base, token, &client, &call).await;
    let error = end_error.as_deref();
    send_ui(ui,"idle",error,"listening","","",0,false,false);
}

async fn finish(base: &str, token: Option<&str>, client: &reqwest::Client, call: &VoiceCall) {
    let transcript = call.transcript.join("\n").chars().take(20000).collect::<String>();
    let _ = api(client,base,token,"POST",&format!("/voice/calls/{}/end",call.id),Some(json!({"transcript":transcript,"anchorMessageId":call.anchor}))).await;
    let _ = call.peer.close().await;
}

async fn api(client: &reqwest::Client, base: &str, token: Option<&str>, method: &str, path: &str, body: Option<Value>) -> Result<Value, String> {
    let url = format!("{}/api{}",base.trim_end_matches('/'),path);
    let mut request = match method { "POST" => client.post(url), _ => client.get(url) };
    if let Some(token) = token.filter(|token| !token.is_empty()) { request=request.bearer_auth(token); }
    if let Some(body) = body { request=request.json(&body); }
    let response=request.send().await.map_err(|error|format!("Voice request failed: {error}"))?;
    let status=response.status();
    let value=response.json::<Value>().await.unwrap_or_else(|_|json!({}));
    if !status.is_success() { return Err(value["error"].as_str().unwrap_or("Voice request failed.").to_owned()); }
    Ok(value)
}

async fn play_remote_audio(track: Arc<TrackRemote>, queue: Arc<Mutex<VecDeque<f32>>>) {
    let Ok(mut decoder) = Decoder::new(RATE, Channels::Stereo) else { return };
    let mut decoded = vec![0f32; RATE as usize * 2 * 120 / 1000];
    while let Ok((packet, _)) = track.read_rtp().await {
        let Ok(samples) = decoder.decode_float(&packet.payload, &mut decoded, false) else { continue };
        if let Ok(mut queue) = queue.lock() {
            for pair in decoded[..samples * 2].chunks_exact(2) { queue.push_back((pair[0] + pair[1]) * 0.5); }
            while queue.len() > RATE as usize * 3 { queue.pop_front(); }
        }
    }
}

fn open_input() -> Result<AudioInput, String> {
    let host=cpal::default_host();
    let device=host.default_input_device().ok_or_else(||"No microphone was found. Connect or enable a microphone and retry.".to_owned())?;
    let supported=device.default_input_config().map_err(|error|format!("Microphone is unavailable: {error}"))?;
    let format=supported.sample_format(); let config:StreamConfig=supported.into();
    let (sender,receiver)=mpsc::channel(8); let muted=Arc::new(AtomicBool::new(false));
    let stream=match format {
        SampleFormat::I8=>input_stream::<i8>(&device,&config,sender,Arc::clone(&muted)), SampleFormat::I16=>input_stream::<i16>(&device,&config,sender,Arc::clone(&muted)),
        SampleFormat::I32=>input_stream::<i32>(&device,&config,sender,Arc::clone(&muted)), SampleFormat::I64=>input_stream::<i64>(&device,&config,sender,Arc::clone(&muted)),
        SampleFormat::U8=>input_stream::<u8>(&device,&config,sender,Arc::clone(&muted)), SampleFormat::U16=>input_stream::<u16>(&device,&config,sender,Arc::clone(&muted)),
        SampleFormat::U32=>input_stream::<u32>(&device,&config,sender,Arc::clone(&muted)), SampleFormat::U64=>input_stream::<u64>(&device,&config,sender,Arc::clone(&muted)),
        SampleFormat::F32=>input_stream::<f32>(&device,&config,sender,Arc::clone(&muted)), SampleFormat::F64=>input_stream::<f64>(&device,&config,sender,Arc::clone(&muted)),
        _=>return Err(format!("Unsupported microphone sample format: {format}")),
    }.map_err(|error|format!("Microphone stream could not start: {error}"))?;
    Ok(AudioInput{_stream:stream,receiver})
}

fn input_stream<T>(device:&cpal::Device,config:&StreamConfig,sender:mpsc::Sender<Vec<i16>>,_muted:Arc<AtomicBool>)->Result<Stream,cpal::BuildStreamError>
where T:SizedSample+Copy, f32:FromSample<T> {
    let channels=config.channels as usize; let rate=config.sample_rate.0 as u64; let mut accumulator=0u64; let mut pending=Vec::<i16>::new();
    device.build_input_stream(config,move |data:&[T],_|{
        for frame in data.chunks(channels.max(1)) {
            let mono=frame.iter().map(|sample|f32::from_sample_(*sample)).sum::<f32>()/frame.len().max(1) as f32;
            accumulator+=RATE as u64;
            while accumulator>=rate { accumulator-=rate; pending.push((mono.clamp(-1.0,1.0)*i16::MAX as f32) as i16); }
            if pending.len()>=FRAME { let packet=pending.drain(..FRAME).collect(); let _=sender.try_send(packet); }
        }
    },|_|{},None)
}

fn open_output() -> Result<AudioOutput,String> {
    let host=cpal::default_host(); let device=host.default_output_device().ok_or_else(||"No speaker or headphones were found.".to_owned())?;
    let supported=device.default_output_config().map_err(|error|format!("Audio output is unavailable: {error}"))?;
    let format=supported.sample_format(); let config:StreamConfig=supported.into(); let channels=config.channels as usize;
    let samples=Arc::new(Mutex::new(VecDeque::<f32>::new())); let muted=Arc::new(AtomicBool::new(false));
    let stream=match format {
        SampleFormat::I8=>output_stream::<i8>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)), SampleFormat::I16=>output_stream::<i16>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)),
        SampleFormat::I32=>output_stream::<i32>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)), SampleFormat::I64=>output_stream::<i64>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)),
        SampleFormat::U8=>output_stream::<u8>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)), SampleFormat::U16=>output_stream::<u16>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)),
        SampleFormat::U32=>output_stream::<u32>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)), SampleFormat::U64=>output_stream::<u64>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)),
        SampleFormat::F32=>output_stream::<f32>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)), SampleFormat::F64=>output_stream::<f64>(&device,&config,channels,Arc::clone(&samples),Arc::clone(&muted)),
        _=>return Err(format!("Unsupported speaker sample format: {format}")),
    }.map_err(|error|format!("Speaker stream could not start: {error}"))?;
    Ok(AudioOutput{_stream:stream,samples,muted})
}

fn output_stream<T>(device:&cpal::Device,config:&StreamConfig,channels:usize,samples:Arc<Mutex<VecDeque<f32>>>,muted:Arc<AtomicBool>)->Result<Stream,cpal::BuildStreamError>
where T:SizedSample, T:FromSample<f32> {
    let mut channel=0usize; let mut current=0.0f32;
    device.build_output_stream(config,move |data:&mut[T],_|{
        if let Ok(mut queue)=samples.lock(){
            for sample in data {
                if channel==0 { current=queue.pop_front().unwrap_or(0.0); }
                *sample=T::from_sample_(if muted.load(Ordering::Relaxed){0.0}else{current});
                channel=(channel+1)%channels.max(1);
            }
        } else { for sample in data { *sample=T::from_sample_(0.0); } }
    },|_|{},None)
}

fn send_ui(ui:&std::sync::mpsc::Sender<(String,Result<Value,String>)>,status:&str,error:Option<&str>,phase:&str,caption:&str,user_caption:&str,elapsed:u64,muted:bool,speaker_muted:bool) {
    let _=ui.send(("voice".into(),Ok(json!({"status":status,"error":error,"phase":phase,"caption":caption,"userCaption":user_caption,"elapsed":elapsed,"muted":muted,"speakerMuted":speaker_muted}))));
}
