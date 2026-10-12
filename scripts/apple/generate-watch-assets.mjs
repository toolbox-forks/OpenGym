import { mkdirSync, writeFileSync, readFileSync, existsSync, copyFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import { CATALOGUE, isAssisted, isLoadedEq, defaultIncrement } from '../../frontend/src/lib/exercises.js'
import { isBw } from '../../frontend/src/lib/history.js'
import { LANGS, baseLang, derivePack } from '../../frontend/src/lib/i18n-core.js'
const root=fileURLToPath(new URL('../../',import.meta.url)), dest=join(root,'apple/WatchApp/Resources')
const check=process.argv.includes('--check')
function output(name,value) {
  const text=JSON.stringify(value)+'\n',path=join(dest,name)
  if(check) {if(!existsSync(path)||readFileSync(path,'utf8')!==text) throw Error('Stale Watch resource: '+name)}
  else {mkdirSync(dest,{recursive:true});writeFileSync(path,text)}
}
const catalogue=Object.fromEntries(CATALOGUE.map(ex=>[ex.id,{...ex,facts:{assisted:isAssisted(ex.id),loaded:isLoadedEq(ex.id),bodyweight:isBw(ex.id),cardio:ex.bp==='cardio',increment:defaultIncrement(ex.id,'kg')},
  mediaAttribution:'© Gym visual',textAttribution:ex.textSource==='exercisedb'?'hasaneyldrm/exercises-dataset · MIT':'See openGym catalogue acknowledgements'}]))
output('catalogue.json',{schemaVersion:1,exercises:catalogue})
let extensions={}
const extra=join(root,'apple/WatchApp/LocaleExtensions.json')
if(existsSync(extra)) extensions=JSON.parse(readFileSync(extra,'utf8'))
for(const lang of Object.keys(LANGS)) {
  const base=baseLang(lang)
  const load=async dir=>{
    const path=join(root,'frontend/src',dir,base+'.js')
    return existsSync(path)?derivePack(lang,(await import(path)).default):{}
  }
  output('locale-'+lang+'.json',{...(await load('locales')),...(extensions[lang]||{})})
  output('names-'+lang+'.json',await load('exercise-names'))
  output('instructions-'+lang+'.json',await load('instr'))
}
output('manifest.json',{schemaVersion:1,exerciseCount:CATALOGUE.length,languages:Object.keys(LANGS),source:'openGym production CATALOGUE and unchanged language packs',mediaAttribution:'© Gym visual'})
const ex={id:'0027',sets:3,reps:5,weight:60,inc:2.5,rest:3}
const previous={id:'sim-previous',d:'2026-01-01',routineId:'sim-strength',entries:[{id:ex.id,rid:'sim-strength',target:ex,sets:Array.from({length:3},()=>({w:60,r:5,done:true}))}]}
output('seed.json',{unit:'kg',tz:'UTC',lang:'en',restSec:3,effort:'rir',todayRoutineIds:['sim-strength'],workouts:[previous],routines:[
  {id:'sim-strength',name:'Simulator strength',prog:'linear',ex:[ex]},
  {id:'sim-superset',name:'Simulator superset',prog:'off',ex:[{...ex,sets:2,sg:'a',sgRest:3},{...ex,id:'0293',sets:2,sg:'a',sgRest:3}]},
  {id:'sim-time',name:'Simulator timed',prog:'off',ex:[{...ex,mode:'time',sec:30,sets:1},{id:'0685',mode:'cardio',min:10,sets:1}]}
]})
if(!check) {
  mkdirSync(join(dest,'thumbnails'),{recursive:true})
  for(const id of ['0027','0293','0685']) copyFileSync(join(root,'catalogue/media/still',id+'.webp'),join(dest,'thumbnails',id+'.webp'))
  copyFileSync(join(root,'catalogue/media/NOTICE.md'),join(dest,'MEDIA_NOTICE.md'))
}
console.log('Watch resources: '+CATALOGUE.length+' text records; '+Object.keys(LANGS).length+' selectable locales; original media notices retained.')
