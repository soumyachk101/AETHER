mod server;

use std::{cell::RefCell, rc::Rc, time::{Duration, Instant}};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::WindowBuilder,
};
use wry::WebViewBuilder;

fn main() {
    let event_loop = EventLoop::new();
    let window = match WindowBuilder::new().with_title("AETHER").build(&event_loop) {
        Ok(w) => w,
        Err(e) => { eprintln!("AETHER: could not create window: {e}"); return; }
    };
    let (url, supervisor, failure) = match server::launch() {
        Ok((url, child)) => (url, child, None),
        Err(e) => ("about:blank".to_string(), None, Some(e)),
    };
    let webview = if let Some(message) = failure.as_ref() {
        server::record_failure(message);
        WebViewBuilder::new().with_html(&server::error_page(message))
            .with_navigation_handler(|uri| uri == "about:blank")
            .build(&window)
    } else {
        let origin = url.split('/').take(3).collect::<Vec<_>>().join("/");
        WebViewBuilder::new().with_url(&url)
            .with_navigation_handler(move |uri| {
                if uri.starts_with(&origin) { true }
                else { let _ = webbrowser::open(&uri); false }
            })
            .build(&window)
    };
    let webview = match webview { Ok(v) => v, Err(e) => { server::record_failure(&format!("Webview startup failed: {e}")); eprintln!("AETHER: webview startup failed: {e}"); return; } };
    let webview = Rc::new(webview);
    let supervisor = Rc::new(RefCell::new(supervisor));
    let sup = supervisor.clone();
    let view = webview.clone();
    let mut next_check = Instant::now();
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(next_check);
        match event {
            Event::MainEventsCleared if Instant::now() >= next_check => {
                next_check = Instant::now() + Duration::from_secs(1);
                if let Some(message) = server::check_exit(&mut sup.borrow_mut()) {
                    let escaped = message.replace('\\', "\\\\").replace('\'', "\\'");
                    let script = format!("document.body.innerHTML='<h1>AETHER server stopped</h1><p>{escaped}</p>'");
                    let _ = view.evaluate_script(&script);
                }
            }
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                server::stop(sup.borrow_mut());
                *control_flow = ControlFlow::Exit;
            }
            Event::LoopDestroyed => server::stop(sup.borrow_mut()),
            _ => {}
        }
    });
}
