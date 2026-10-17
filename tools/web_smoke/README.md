Headless-Chrome smoke test for the Web build (renders with SwiftShader WebGL2,
takes a screenshot, simulates a touch tap, takes another).

    cd tools/web_smoke && npm init -y && npm i puppeteer-core@23
    python3 -m http.server -d ../../build/web 8765 &
    node shot.js ../../screenshots/m1_web_chrome.png ../../screenshots/m1_web_after_tap.png
