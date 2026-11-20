// The real network for the CLI and the model of the server's /scrapers/fetch proxy: one request,
// redirects followed by hand so every hop goes through the guard, size and time capped.
import { LIMITS, TRUNCATED, checkUrl, upgradeUrl } from './guard.mjs';

export async function doFetch(req, limits = LIMITS) {
  let url = upgradeUrl(req.url);
  let method = req.method;
  let body = req.body;
  for (let hop = 0; hop <= limits.redirects; hop++) {
    const refused = checkUrl(url);
    if (refused) throw new Error(refused);
    const response = await fetch(url, {
      method,
      headers: req.headers,
      body: method === 'GET' || method === 'HEAD' ? undefined : body ?? undefined,
      redirect: 'manual',
      signal: AbortSignal.timeout(limits.requestMs),
    });
    const location = response.headers.get('location');
    if (response.status >= 300 && response.status < 400 && location && req.redirect !== 'manual') {
      url = upgradeUrl(new URL(location, url).href);
      if (response.status !== 307 && response.status !== 308) {
        method = 'GET';
        body = null;
      }
      continue;
    }
    const chunks = [];
    let size = 0;
    let cut = false;
    for await (const chunk of response.body ?? []) {
      if (size + chunk.length > limits.responseBytes) {
        chunks.push(chunk.subarray(0, limits.responseBytes - size));
        cut = true;
        break;
      }
      size += chunk.length;
      chunks.push(chunk);
    }
    const headers = {};
    response.headers.forEach((v, k) => (headers[k] = v));
    return {
      status: response.status,
      statusText: response.statusText,
      headers,
      body: Buffer.concat(chunks).toString('utf8') + (cut ? TRUNCATED : ''),
      url,
    };
  }
  throw new Error('trop de redirections');
}
