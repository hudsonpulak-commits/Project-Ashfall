const puppeteer = require('puppeteer-core');
(async () => {
  const b = await puppeteer.launch({executablePath: '/usr/bin/google-chrome', headless: 'new',
    args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist']});
  const p = await b.newPage();
  await p.setViewport({width: 390, height: 844, deviceScaleFactor: 1, isMobile: true, hasTouch: true});
  const logs = [];
  p.on('console', m => logs.push(m.type() + ': ' + m.text()));
  p.on('pageerror', e => logs.push('PAGEERROR: ' + e.message));
  await p.goto('http://localhost:8765/index.html', {waitUntil: 'load'});
  await new Promise(r => setTimeout(r, 20000));
  await p.screenshot({path: process.argv[2]});
  // tap a tile above the player to test touch-walk
  await p.touchscreen.tap(195, 300);
  await new Promise(r => setTimeout(r, 4000));
  await p.screenshot({path: process.argv[3]});
  console.log(logs.filter(l => !/^debug/.test(l)).slice(0, 40).join('\n'));
  await b.close();
})();
