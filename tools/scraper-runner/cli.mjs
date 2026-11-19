// node cli.mjs <scraper.js> <tmdbId> <movie|tv> [season] [episode]
// Runs a scraper for real (network included, through the guard) and prints its streams: the
// quick way for a scraper author to try a file before putting it in a repository.
import { readFile } from 'node:fs/promises';
import { runScraper } from './host.mjs';
import { doFetch } from './net.mjs';

const [file, tmdbId, mediaType, season, episode] = process.argv.slice(2);
if (!file || !tmdbId || !['movie', 'tv'].includes(mediaType)) {
  console.error('usage: node cli.mjs <scraper.js> <tmdbId> <movie|tv> [season] [episode]');
  process.exit(2);
}
const streams = await runScraper({
  code: await readFile(file, 'utf8'),
  params: { tmdbId, mediaType, season: season ? Number(season) : null, episode: episode ? Number(episode) : null },
  doFetch,
  onLog: ({ level, msg }) => console.error(`[${level}] ${msg}`),
});
console.log(JSON.stringify(streams, null, 2));
