import '../assets/sgfs-releases.js';

const [version] = process.argv.slice(2);
const current = globalThis.SGFSReleases[0];
if (version !== 'v' + current.version) throw Error('A tag precisa corresponder à versão atual do SGFS.');
console.log('# SGFS ' + current.version + '\n\n' + current.changes.map(change => '- ' + change).join('\n'));
