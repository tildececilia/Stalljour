// Enkel lokal utvecklingsserver för appen (bara för test lokalt).
// Kör:  node dev-server.js   → öppna http://localhost:5178
const http = require("http"), fs = require("fs"), path = require("path");
const root = path.join(__dirname, "docs");
const types = { ".html":"text/html", ".js":"text/javascript", ".css":"text/css", ".json":"application/json", ".svg":"image/svg+xml" };
http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p === "/") p = "/index.html";
  const fp = path.join(root, p);
  if (!fp.startsWith(root)) { res.writeHead(403); res.end("forbidden"); return; }
  fs.readFile(fp, (e, data) => {
    if (e) { res.writeHead(404); res.end("404"); return; }
    res.writeHead(200, { "content-type": types[path.extname(fp)] || "application/octet-stream" });
    res.end(data);
  });
}).listen(5178, () => console.log("Stalljour dev: http://localhost:5178"));
