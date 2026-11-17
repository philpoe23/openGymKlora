// Writes assets/exercises.json from the web app's generated exercise library (EXDB), plus the two
// small tables exercises.js reads beside it: assets/exercise-aliases.json (EXALIAS, the id of a
// drawing → the exercise it draws) and assets/catalogue-v13-ids.json (the v1.3 catalogue ids the
// search ranks first among equals).
// Run from app/: node tool/export_exercises.mjs
import fs from 'node:fs'
import { EXDB, EXALIAS } from '../../frontend/src/lib/exercises-data.js'
const out = name => new URL('../assets/' + name, import.meta.url)
fs.writeFileSync(out('exercises.json'), JSON.stringify(EXDB))
fs.writeFileSync(out('exercise-aliases.json'), JSON.stringify(EXALIAS))
fs.copyFileSync(new URL('../../frontend/src/lib/catalogue-v13-ids.json', import.meta.url), out('catalogue-v13-ids.json'))
console.log('exercises:', EXDB.length, 'aliases:', Object.keys(EXALIAS).length)
