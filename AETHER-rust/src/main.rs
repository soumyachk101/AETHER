mod server;

use std::{cell::RefCell, rc::Rc, time::{Duration, Instant}};
use tao::{
    dpi::LogicalSize,
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::WindowBuilder,
};
use wry::WebViewBuilder;

fn main() {
    let event_loop = EventLoop::new();
    let window = match WindowBuilder::new()
        .with_title("AETHER")
        .with_inner_size(LogicalSize::new(1280.0, 840.0))
        .build(&event_loop)
    {
        Ok(w) => w,
        Err(e) => {
            eprintln!("AETHER: could not create window: {e}");
            return;
        }
    };

    let (url, supervisor, failure) = match server::launch() {
        Ok((url, child)) => (url, child, None),
        Err(e) => ("about:blank".to_string(), None, Some(e)),
    };

    let webview = if let Some(message) = failure.as_ref() {
        server::record_failure(message);
        WebViewBuilder::new()
            .with_html(&server::error_page(message))
            .with_navigation_handler(|uri| uri == "about:blank")
            .build(&window)
    } else {
        let origin = url.split('/').take(3).collect::<Vec<_>>().join("/");
        let mut builder = WebViewBuilder::new();
        builder = builder.with_url(&url);

        if let Some(token) = server::owner_token() {
            let escaped = token.replace('\\', "\\\\").replace('\'', "\\'");
            let script = format!(
                "try {{ sessionStorage.setItem('aether-token', '{escaped}'); sessionStorage.setItem('opendots-token', '{escaped}'); }} catch (e) {{}}"
            );
            builder = builder.with_initialization_script(&script);
        }

        builder = builder.with_navigation_handler(move |uri| {
            if uri.starts_with(&origin)
                || uri.starts_with("data:")
                || uri.starts_with("blob:")
                || uri == "about:blank"
            {
                true
            } else {
                let _ = webbrowser::open(&uri);
                false
            }
        });

        builder.build(&window)
    };

    let webview = match webview {
        Ok(v) => v,
        Err(e) => {
            server::record_failure(&format!("Webview startup failed: {e}"));
            eprintln!("AETHER: webview startup failed: {e}");
            return;
        }
    };

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
                    let script = format!(
                        "document.body.innerHTML='<div style=\"font-family:system-ui;max-width:600px;margin:20vh auto;padding:32px;background:#18181b;color:#f4f4f5;border-radius:12px;border:1px solid #27272a\"><h2>AETHER server stopped</h2><p style=\"color:#a1a1aa\">{escaped}</p></div>'"
                    );
                    let _ = view.evaluate_script(&script);
                }
            }
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => {
                server::stop(&mut sup.borrow_mut());
                *control_flow = ControlFlow::Exit;
            }
            Event::LoopDestroyed => server::stop(&mut sup.borrow_mut()),
            _ => {}
        }
    });
}
