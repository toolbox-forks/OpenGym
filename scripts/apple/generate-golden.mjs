import { writeFileSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { estimate1RM } from '../../frontend/src/lib/onerm.js'
import { plateStack } from '../../frontend/src/lib/plates.js'
import { convertWeight, convertBodyWeight } from '../../frontend/src/lib/units.js'
import { insertWarmupRow } from '../../frontend/src/lib/history.js'
import { readSession, nextPrescription } from '../../frontend/src/lib/progression.js'
import { EXDB, isAssisted, defaultIncrement, isLoadedEq } from '../../frontend/src/lib/exercises.js'

export function generateGolden() {
  const cases=[]
  const add=(kind,input,expected) => cases.push(JSON.parse(JSON.stringify({kind,input,expected})))
  for(const w of [0,20,60,125.5]) for(const r of [0,1,2,5,8,12,13,15,16])
    for(const formula of ['epley','brzycki','lombardi','oconner','mayhew','wathan','lander','weighted','unknown'])
      for(const rir of [null,0,2]) add('oneRM',{w,r,formula,rir},estimate1RM(w,r,formula,rir))
  for(const w of [0,0.25,20,62.5,397]) for(const from of ['kg','lb']) for(const to of ['kg','lb']) {
    add('units',{w,from,to},convertWeight(w,from,to)); add('bodyUnits',{w,from,to},convertBodyWeight(w,from,to))
  }
  const inventories=[[{w:20,n:3},{w:10,n:2},{w:5,n:2},{w:2.5,n:2},{w:1.25,n:2}], [{w:4,n:1},{w:3,n:2}], [{w:45,n:2},{w:10,n:2},{w:2.5,n:2}], []]
  for(const inventory of inventories) for(const w of [0,1.1,5.25,6,17.5,42.5,100,9999]) add('plates',{w,inventory},plateStack(w,inventory))
  for(const weight of [0,10,20,60,100]) for(const count of [0,1,3,5]) for(const floor of [0,20]) {
    let rows=[{w:weight,r:5,done:false}]
    for(let i=0;i<count;i++) rows=insertWarmupRow(rows,'reps',{reps:5},2.5,floor)
    add('warmups',{weight,count,step:2.5,floor},rows.slice(0,count).map(r=>r.w))
  }
  // Same plainly loaded-lift classification and hist construction as progression.test.js.
  const lift=EXDB.find(e=>e.bp!=='cardio'&&!['upper legs','lower legs','back','hips','glutes'].includes(e.bp)&&!['body weight','band','resistance band'].includes(e.eq)&&!isAssisted(e.id)).id
  const hist=(rows,target) => ({unit:'kg',workouts:rows.map((row,i)=>({d:`2026-01-${String(i+1).padStart(2,'0')}`,entries:[{id:lift,target:target||{sets:3,reps:5,weight:row[0]},sets:row.slice(1).map(r=>({w:row[0],r:r??0,done:r!==null}))}]}))})
  const facts={assisted:isAssisted(lift),loaded:isLoadedEq(lift),increment:defaultIncrement(lift,'kg')}
  for(const row of [[60,5,5,6],[60,5,5,3],[60,5,5,null],[60,5,5],[60,5,5,5,1]]) {
    const entry=hist([row]).workouts[0].entries[0]
    add('readSession',{entry,fallback:{},facts},readSession(entry,{}))
  }
  for(const mode of ['time','reps']) for(const side of [false,true]) {
    const target={mode,side,sets:2,...(mode==='time'?{sec:30}:{reps:8})}
    const entry={id:lift,target,sets:Array.from({length:mode==='time'&&side?4:2},()=>({w:20,r:8,sec:30,done:true}))}
    add('readSession',{entry,fallback:{},facts},readSession(entry,{}))
    entry.sets.push({w:0,r:0,done:false,phase:'warmup',warmup:true})
    add('readSession',{entry,fallback:{},facts},readSession(entry,{}))
  }
  for(const prog of ['off','linear','greyskull','double','triple','time']) {
    const cfg={id:lift,sets:3,reps:5,weight:60,inc:2.5,prog,...(prog==='time'?{mode:'time',sec:30,inc:5}:{}),...(prog==='double'||prog==='triple'?{reps:12,repsMin:8,setsMax:5}:{})}
    for(const rows of [[],[[60,5,5,5]],[[60,5,5,12]],[[60,5,5,3]],[[60,3,3,3],[60,3,3,3],[60,3,3,3]],[[60,12,12,12]]]) {
      const state=hist(rows,prog==='double'||prog==='triple'?{sets:3,reps:cfg.reps,repsMin:8}:undefined)
      if(prog==='time') state.workouts.forEach(w=>w.entries.forEach(e=>{e.target={sets:3,sec:30,mode:'time'};e.sets.forEach(s=>{s.sec=s.r*6;delete s.r})}))
      add('progression',{state,cfg,routine:{},facts},nextPrescription(state,cfg,{}))
    }
  }
  return cases
}
const destination=fileURLToPath(new URL('../../apple/OpenGymKit/Tests/OpenGymKitTests/Fixtures/golden.json',import.meta.url))
if(process.argv[1]===fileURLToPath(import.meta.url)) {
  const encoded=JSON.stringify(generateGolden(),null,2)+'\n'
  if(process.argv.includes('--check')) { if(readFileSync(destination,'utf8')!==encoded) throw Error('Golden fixtures drifted: regenerate and review both implementations');console.log('Golden fixtures match production JS') }
  else {writeFileSync(destination,encoded);console.log(`${generateGolden().length} shared golden cases written`)}
}
