use std::sync::Arc;

use judgement_persistence::MemoryStore;
use judgement_server::build_router;
use judgement_server::state::AppState;
use tokio::net::TcpListener;

async fn serve() -> String {
    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    let app = build_router(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

#[tokio::test]
async fn photo_proxy_rejects_missing_and_foreign_urls() {
    let base = serve().await;
    let client = reqwest::Client::new();

    let missing = client
        .get(format!("{base}/api/v1/photos"))
        .send()
        .await
        .unwrap();
    assert_eq!(missing.status(), 404);

    let evil = client
        .get(format!(
            "{base}/api/v1/photos?u=https://evil.example/pic.png"
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(evil.status(), 404);

    let google = client
        .get(format!(
            "{base}/api/v1/photos?u=https://lh3.googleusercontent.com/a/x"
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(google.status(), 404);

    let http = client
        .get(format!(
            "{base}/api/v1/photos?u=http://t.me/i/userpic/320/x"
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(http.status(), 404);
}
