import Foundation

/// Catalogue facts are supplied by the same snapshot that carries exercise ids/text.
/// This avoids maintaining a second, drifting database of equipment classifications.
public struct ExerciseFacts: Codable, Sendable {
    public var assisted: Bool = false
    public var loaded: Bool = true
    public var bodyweight: Bool = false
    public var cardio: Bool = false
    public var increment: Double = 2.5
    public var owned: [Double]? = nil
    public init(assisted: Bool = false, loaded: Bool = true, bodyweight: Bool = false, cardio: Bool = false, increment: Double = 2.5, owned: [Double]? = nil) {
        self.assisted=assisted;self.loaded=loaded;self.bodyweight=bodyweight;self.cardio=cardio;self.increment=increment;self.owned=owned
    }
    public init(from decoder: Decoder) throws {
        let x=try JSONValue(from:decoder)
        self.init(assisted:x.flag("assisted"),loaded:x["loaded"].boolValue,bodyweight:x.flag("bodyweight"),cardio:x.flag("cardio"),increment:x.number("increment",default:2.5),owned:x["owned"] == .null ? nil : x.rows("owned").compactMap(\.doubleValue))
    }
}
public enum Progression {
    private static func mode(_ target: JSONValue, _ facts: ExerciseFacts) -> String {
        let m=target.text("mode");return ["reps","time","cardio"].contains(m) ? m : facts.cardio ? "cardio" : "reps"
    }
    private static func warm(_ row: JSONValue) -> Bool { row.flag("warmup") || row.text("phase")=="warmup" }
    private static func backoff(_ top: Double, _ index: Int, _ step: Double) -> Double {
        guard top>0,step>0,index>0 else {return top}
        let raw=top-Double(index)*step
        let onGrid=abs(top-TrainingMath.jsRound(top/step)*step)<=0.1
        return max(min(top,step),onGrid ? TrainingMath.snap(raw,step:step) : TrainingMath.round1(raw))
    }
    public static func readSession(entry: JSONValue, fallback: JSONValue = .object([:]), facts: ExerciseFacts) -> JSONValue {
        let target=entry["target"] == .null ? fallback : entry["target"]
        let m=mode(target,facts), logged=entry.rows("sets").filter { !warm($0) }
        let rowGoals=m=="reps" && entry["target"] != .null ? target.rows("rowReps").map {max(0,$0.doubleValue ?? 0)} : []
        let plannedRows=rowGoals.isEmpty ? target.number("sets",default:Double(logged.count)) : Double(rowGoals.count)
        let planned=m=="time" && target.flag("side") ? plannedRows*2 : plannedRows
        let enough=Double(logged.count)>=planned
        let rows=entry["target"] != .null ? Array(logged.prefix(max(1,Int(planned)))) : logged
        let loads=rows.filter {$0.flag("done")}.map {$0.number("w")}
        let weight=facts.assisted ? loads.filter {$0>0}.min() ?? 0 : max(0,loads.max() ?? 0)
        if m=="time" {
            let goal=target.number("sec"),held=rows.map {$0.flag("done") ? $0.number("sec") : 0}
            return .object(["mode":.string(m),"target":target,"goal":.number(goal),"held":.array(held.map(JSONValue.number)),"weight":.number(weight),"best":.number(max(0,held.max() ?? 0)),"ok":.bool(goal>0 && enough && !held.isEmpty && held.allSatisfy {$0>=goal})])
        }
        let goal=rowGoals.max() ?? target.number("reps"),step=entry["target"] != .null ? target.number("backoffStep") : 0
        let top=step>0 ? rows.first?.number("w") ?? 0 : 0
        let reps=rows.enumerated().map {i,s in s.flag("done") && (top<=0 || i==0 || s.number("w")>=backoff(top,i,step)-0.05) ? s.number("r") : 0}
        let ok=goal>0 && enough && !reps.isEmpty && reps.enumerated().allSatisfy {i,r in r >= (i<rowGoals.count ? rowGoals[i] : goal)}
        return .object(["mode":.string(m),"target":target,"goal":.number(goal),"reps":.array(reps.map(JSONValue.number)),"weight":.number(weight),"count":.number(Double(reps.count)),"low":.number(reps.min() ?? 0),"amrap":.number(reps.last ?? 0),"ok":.bool(ok)])
    }
    private static func planned(_ cfg: JSONValue, _ facts: ExerciseFacts) -> JSONValue {
        var p:[String:JSONValue]=["sets":.number(max(1,cfg.number("sets",default:1)))]
        for key in ["reps","repsMin","setsMax"] where mode(cfg,facts)=="reps" && cfg.number(key)>0 {p[key]=cfg[key]}
        if mode(cfg,facts)=="time" && cfg.number("sec")>0 {p["sec"]=cfg["sec"]}
        if cfg["weight"] != .null {p["weight"]=cfg["weight"]}
        return .object(p)
    }
    private static func samePlan(_ a: JSONValue,_ b: JSONValue) -> Bool { ["sets","reps","repsMin","sec","setsMax"].allSatisfy {a[$0]==b[$0]} }
    private static func range(_ cfg: JSONValue,_ fallback: Double,_ stride: Double) -> (top:Double,bottom:Double) {
        let upper=cfg.number("reps")>0 ? max(stride,ceil(TrainingMath.jsRound(cfg.number("reps"))/stride)*stride) : max(stride,ceil(fallback/stride)*stride)
        let low=cfg.number("repsMin")>0 ? cfg.number("repsMin") : max(1,upper-2)
        let lower=max(stride,ceil(TrainingMath.jsRound(low)/stride)*stride)
        return lower>=upper ? (lower+stride,lower) : (upper,lower)
    }
    private static func activeTriple(_ s: JSONValue) -> Double {
        let rows=s["target"].rows("rowReps").compactMap(\.doubleValue),reps=s.rows("reps").compactMap(\.doubleValue)
        if rows.isEmpty {return s.number("low")}
        if rows.allSatisfy({$0==rows[0]}) {return rows.indices.map {$0<reps.count ? reps[$0] : 0}.min() ?? 0}
        return rows.count<=reps.count ? reps[rows.count-1] : 0
    }
    private static func stalls(_ sessions:[JSONValue],_ policy:String) -> Int {
        var n=0
        for i in sessions.indices.reversed() {
            let s=sessions[i]
            if s.flag("ok") {break}
            if i<sessions.count-1 {
                let next=sessions[i+1]
                if s.number("weight") != next.number("weight") {break}
                if s["planned"] != .null && next["planned"] != .null && !samePlan(s["planned"],next["planned"]) {break}
            }
            if policy=="double" || policy=="triple" {
                var previous:[Double]=[]
                if i>0 {for j in stride(from:i-1,through:0,by:-1) {
                    let old=sessions[j]
                    if old.number("weight") != s.number("weight") {break}
                    if policy=="triple" && old["target"]["rowReps"] != s["target"]["rowReps"] {break}
                    previous.append(policy=="double" ? old.number("low") : activeTriple(old))
                }}
                let value=policy=="double" ? s.number("low") : activeTriple(s)
                if let best=previous.max(),value>best {break}
            }
            n+=1
        }
        return n
    }
    private static func grid(_ ideal:Double,_ step:Double,_ maxWeight:Double,_ strict:Bool,_ owned:[Double]?) -> [Double] {
        guard ideal>0,step>0,maxWeight>0 else {return []}
        let valid:(Double)->Bool={$0>0 && $0<=maxWeight+1e-9 && (!strict || $0<maxWeight-1e-9)}
        if let owned {
            let good=owned.filter(valid)
            return Array(Set([good.filter {$0<=ideal+1e-9}.max(),good.filter {$0>=ideal-1e-9}.min()].compactMap {$0})).sorted()
        }
        return Array(Set([floor(ideal/step)*step,ceil(ideal/step)*step].map {TrainingMath.snap($0,step:step)})).filter(valid).sorted()
    }
    private static func deload(_ current:Double,_ cfg:JSONValue,_ target:JSONValue,_ step:Double,_ policy:String,_ owned:[Double]?) -> (weight:Double,reps:Double,targetRM:Double,factor:Double)? {
        let side=target.flag("side"),stride=side ? 2.0 : 1.0,upper=max(stride,ceil(target.number("reps")/stride)*stride)
        guard target.number("weight")>0,upper>0,current>0,step>0 else {return nil}
        let factor=cfg.number("deloadFactor")>=0.5 && cfg.number("deloadFactor")<=0.95 ? cfg.number("deloadFactor") : 0.9
        let targetRM=TrainingMath.round1(TrainingMath.round1(target.number("weight")*(1+(side ? upper/2 : upper)/30))*factor)
        let r=range(target,upper,stride),top=policy=="double" ? min(r.top,max(r.bottom,upper)) : upper,bottom=policy=="double" ? r.bottom : top
        var options:[(w:Double,r:Double,error:Double,change:Double)]=[]
        for reps in Swift.stride(from:top,through:bottom,by:-stride) {
            let ideal=targetRM/(1+(side ? reps/2 : reps)/30),allow=policy=="double" && reps<upper
            var weights=grid(ideal,step,current,!allow,owned)
            if allow && !weights.contains(current) {weights.append(current)}
            for w in weights {options.append((w,reps,abs(TrainingMath.round1(w*(1+(side ? reps/2 : reps)/30))-targetRM),abs(reps-upper)))}
        }
        if options.isEmpty {for reps in Swift.stride(from:top,through:bottom,by:-stride) {options.append((current,reps,abs(TrainingMath.round1(current*(1+(side ? reps/2 : reps)/30))-targetRM),abs(reps-upper)))}}
        let best=options.sorted {a,b in a.error != b.error ? a.error<b.error : a.change != b.change ? a.change<b.change : a.w != b.w ? a.w>b.w : a.r>b.r}.first
        return best.map {($0.w,$0.r,targetRM,factor)}
    }
    public static func next(state:JSONValue,cfg:JSONValue,routine:JSONValue = .object([:]),facts:ExerciseFacts) -> JSONValue {
        let m=mode(cfg,facts),unit=state.text("unit",default:"kg"),stride=cfg.flag("side") ? 2.0 : 1.0
        let allowed=m=="time" ? ["off","time"] : m=="cardio" ? ["off"] : ["off","linear","greyskull","double","triple"]
        let picked=cfg.text("prog",default:routine.text("prog",default:m=="reps" ? "linear" : "off"))
        let policy=cfg.rows("pyramid").isEmpty && allowed.contains(picked) ? picked : "off"
        let step=cfg.number("inc")>0 ? cfg.number("inc") : m=="time" ? 5 : facts.increment
        func output(_ kind:String,_ fields:[String:JSONValue]=[:],_ why:[JSONValue]=[]) -> JSONValue {
            var value=fields;value["policy"] = .string(policy);value["kind"] = .string(kind);if !why.isEmpty {value["why"] = .array(why)};return .object(value)
        }
        if policy=="off" {return output("off")}
        let id=cfg.text("id"),rid=routine.text("id")
        func history(_ own:Bool) -> [JSONValue] {
            state.rows("workouts").compactMap {w in
                let entries=w.rows("entries")
                func slot(_ e:JSONValue)->String {if !e.text("rid").isEmpty {return e.text("rid")};if entries.contains(where:{!$0.text("rid").isEmpty}) {return ""};return w.rows("routineIds").first?.stringValue ?? w.text("routineId")}
                guard let e=entries.first(where:{$0.text("id")==id && (!own || slot($0)==rid)}),!w.flag("excludeFromProgression"),!e.flag("noProg"),e.rows("sets").contains(where:{$0.flag("done") && !warm($0)}) else {return nil}
                var s=readSession(entry:e,fallback:cfg,facts:facts);s["d"]=w["d"];if !slot(e).isEmpty {s["rid"] = .string(slot(e))};if e["planned"] != .null {s["planned"]=e["planned"]};return s
            }.filter {$0.text("mode")==m}
        }
        let own=rid.isEmpty ? [] : history(true),sessions=own.isEmpty ? history(false) : own
        let triple=policy=="triple" && m=="reps",r3=range(cfg,10,stride)
        let base=max(1,Int(TrainingMath.jsRound(cfg.number("sets",default:1)))),ceiling=max(base,min(10,Int(TrainingMath.jsRound(cfg.number("setsMax",default:Double(base))))))
        func rows(_ value:Double)->JSONValue {.array(Array(repeating:.number(value),count:base))}
        guard let last=sessions.last else {return triple ? output("first",["reps":.number(r3.bottom),"sets":.number(Double(base)),"rowReps":rows(r3.bottom)],[.string("Nothing logged yet, so this session sets the baseline.")]) : output("first",[:],[.string("Nothing logged yet, so this session sets the baseline.")])}
        let bw=cfg["bodyweight"] == .null ? facts.bodyweight : cfg.flag("bodyweight"),climbs=bw || !facts.loaded || facts.assisted
        let w=last.number("weight"),count=stalls(sessions,policy),deloadAt=policy=="greyskull" ? 1 : 3
        let owned=facts.assisted ? nil : facts.owned?.sorted()
        func harder(_ weight:Double,_ doubleJump:Bool=false)->Double {
            if facts.assisted {return TrainingMath.addStep(weight,by: -(doubleJump ? step*2 : step),increment:step)}
            if let owned {let above=owned.filter {$0>weight+1e-9};return above.count >= (doubleJump ? 2 : 1) ? above[doubleJump ? 1 : 0] : weight}
            return TrainingMath.addStep(weight,by:doubleJump ? step*2 : step,increment:step)
        }
        func easier(_ weight:Double)->Double {
            if facts.assisted {return TrainingMath.addStep(weight,by:step,increment:step)}
            if let owned {return owned.filter {$0<weight-1e-9}.sorted {abs($0-weight*0.9) != abs($1-weight*0.9) ? abs($0-weight*0.9)<abs($1-weight*0.9) : $0>$1}.first ?? weight}
            let candidate=TrainingMath.snap(weight*0.9,step:step)
            return max(step,candidate>=weight ? TrainingMath.snap(weight-step,step:step) : candidate)
        }
        let borrowed = !rid.isEmpty && last.text("rid") != rid
        if last["planned"] != .null ? !samePlan(last["planned"],planned(cfg,facts)) : borrowed {
            let why:[JSONValue]=[.string(borrowed ? "First time in this routine, so starting from its own target." : "Plan changed, so starting from your new target.")]
            let changed=cfg.number("weight")>0 && last["planned"] != .null && last["planned"]["weight"] != cfg["weight"]
            var f:[String:JSONValue]=[:]
            if changed {f["weight"]=cfg["weight"]} else if w>0 {f["weight"] = .number(w)} else if climbs {f["weight"] = .number(0)} else if cfg.number("weight")>0 {f["weight"]=cfg["weight"]}
            if m=="time" {f["sec"]=cfg["sec"] == .null ? last["goal"] : cfg["sec"]}
            else if policy=="double" || triple {let r=range(cfg,last.number("goal",default:10),stride),aim=changed ? r.bottom : min(r.top,max(r.bottom,last.number("low")+stride));f["reps"] = .number(aim);if triple {f["sets"] = .number(Double(base));f["rowReps"]=rows(aim)}}
            else if cfg.number("reps")>0 {f["reps"]=cfg["reps"]}
            return output("hold",f,why)
        }
        if m=="time" {
            let goal=last.number("goal")>0 ? last.number("goal") : cfg.number("sec")
            if last.flag("ok") {return output("up",["sec":.number(goal+step)],[.string("Held every set for the full time. Target goes up by {0}s."),.number(step)])}
            if count>=deloadAt {let candidate=TrainingMath.snap(goal*0.9,step:5);let sec=max(5,candidate>=goal ? TrainingMath.snap(goal-5,step:5) : candidate);return output("deload",["sec":.number(sec)],[.string("Short {0} sessions in a row. Back off to {1}s and build up again."),.number(Double(count)),.number(sec)])}
            return output("hold",["sec":.number(goal)],[.string("Came up short last time. Same target again.")])
        }
        if w<=0 && climbs {
            let goal=last.number("goal")>0 ? last.number("goal") : cfg.number("reps"),planSets=max(1,cfg.number("sets",default:1))
            let reached=last["planned"] != .null ? max(planSets,last["target"].number("sets")) : planSets
            var f:[String:JSONValue]=["weight":.number(0)]
            if reached>planSets {f["sets"] = .number(reached)}
            if !last.flag("ok") || goal<=0 {if goal>0 {f["reps"] = .number(goal)};return output("hold",f,[.string("Bodyweight: same target again until every set is clean.")])}
            if cfg.number("repsMax")>0 && goal>=cfg.number("repsMax") {
                if reached+1<=6 {let bottom=max(1,min(cfg.number("reps",default:cfg.number("repsMax")),cfg.number("repsMax")));f["sets"] = .number(reached+1);f["reps"] = .number(bottom);return output("up",f,[.string("{0} reps in every set! Add a set and go back to {1}."),.number(goal),.number(bottom)])}
                f["reps"] = .number(goal);return output("hold",f,[.string("{0} sets of {1}. Time to add weight or try a harder variation."),.number(reached),.number(goal)])
            }
            f["reps"] = .number(goal+stride);return output("up",f,[.string("Bodyweight: every rep last time, so go for {0} this time."),.number(goal+stride)])
        }
        if w<=0 {return output("hold",cfg.number("weight")>0 ? ["weight":cfg["weight"]] : [:],[.string("No weight logged last time. Enter what you lift and progression takes it from there.")])}
        func epleyDeload()->JSONValue? {
            guard !facts.assisted,!bw,policy=="linear" || policy=="double",cfg["intensifier"].text("type") != "restpause" else {return nil}
            var target=cfg;for (key,value) in last["target"].objectValue {target[key]=value}
            target["sets"]=cfg["sets"]
            guard let chosen=deload(w,cfg,target,step,policy,owned) else {return nil}
            return output("deload",["weight":.number(chosen.weight),"reps":.number(chosen.reps),"sets":target["sets"],"target1RM":.number(chosen.targetRM),"deloadFactor":.number(chosen.factor)],[.string(chosen.weight>=w ? "Stuck for {0} sessions. Hold {1} {2} and use {3} reps." : "Stuck for {0} sessions. Epley deload to {1} {2} for {3} reps."),.number(Double(count)),.number(chosen.weight),.string(unit),.number(chosen.reps)])
        }
        if triple {
            let ownRows=last["target"].rows("rowReps").compactMap(\.doubleValue)
            let n=min(ceiling,max(base,Int(last["target"].number("sets",default:Double(base)))))
            let aims=ownRows.isEmpty ? Array(repeating:min(r3.top,max(r3.bottom,last["target"].number("reps",default:last.number("goal",default:r3.bottom)))),count:n) : ownRows
            func out(_ kind:String,_ weight:Double,_ targets:[Double],_ why:[JSONValue])->JSONValue {output(kind,["weight":.number(weight),"reps":.number(targets.first ?? 0),"sets":.number(Double(targets.count)),"rowReps":.array(targets.map(JSONValue.number))],why)}
            if count>=deloadAt {
                let factor=cfg.number("deloadFactor")>=0.5 && cfg.number("deloadFactor")<=0.95 ? cfg.number("deloadFactor") : 0.9
                let rm=TrainingMath.round1(TrainingMath.round1(w*(1+(cfg.flag("side") ? (aims.max() ?? 0)/2 : aims.max() ?? 0)/30))*factor)
                let ideal=rm/(1+(cfg.flag("side") ? r3.bottom/2 : r3.bottom)/30)
                let dw=facts.assisted ? easier(w) : grid(ideal,step,w,true,nil).min(by:{abs($0-ideal)<abs($1-ideal)}) ?? easier(w)
                return out("deload",dw,Array(repeating:r3.bottom,count:base),[.string(facts.assisted ? "Stuck for {0} sessions. Back to {1} {2} of help, start again at {3} sets of {4}." : "Stuck for {0} sessions. Deload to {1} {2} and start again at {3} sets of {4}."),.number(Double(count)),.number(dw),.string(unit),.number(Double(base)),.number(r3.bottom)])
            }
            if !last.flag("ok") {return out("hold",w,aims,count==0 ? [.string("Short of the target, but more reps than before. Same sets and reps again.")] : [.string("Missed reps last time. Same sets and reps again ({0} of {1} to go)."),.number(Double(deloadAt-count)),.number(Double(deloadAt))])}
            let logged=last.rows("reps").compactMap(\.doubleValue),got=aims.enumerated().map {i,r in min(r3.top,max(r,i<logged.count ? logged[i] : 0))}
            if got.count<=base && (got.prefix(base).min() ?? 0)<r3.top {let aim=min(r3.top,max(r3.bottom,(got.prefix(base).min() ?? 0)+stride));return out("hold",w,Array(repeating:aim,count:max(got.count,base)),[.string("Same weight, aim for {0} reps in every set."),.number(aim)])}
            if got.count>base && (got.last ?? 0)<r3.top {let aim=min(r3.top,max(r3.bottom,(got.last ?? 0)+stride));return out("hold",w,Array(repeating:r3.top,count:got.count-1)+[aim],[.string("Same weight, aim for {0} reps on the last set."),.number(aim)])}
            if got.count<ceiling {return out("up",w,Array(repeating:r3.top,count:got.count)+[r3.bottom],[.string("{0} reps in every set! Add a set at {1} reps."),.number(r3.top),.number(r3.bottom)])}
            return out("up",harder(w),Array(repeating:r3.bottom,count:base),[.string(facts.assisted ? "Top of the range on all {0} sets. {1} {2} less help, back to {3} sets of {4}." : "Top of the range on all {0} sets. {1} {2} more, back to {3} sets of {4}."),.number(Double(got.count)),.number(step),.string(unit),.number(Double(base)),.number(r3.bottom)])
        }
        if policy=="double" {
            let r=range(cfg,last.number("goal",default:10),stride)
            if last.flag("ok") && last.number("low")>=r.top {
                let up=harder(w)
                if owned != nil && up==w {return output("hold",["weight":.number(w),"reps":.number(r.top)],[.string("You’ve outgrown the rack: {0} {1} is your heaviest dumbbell, so the weight stays."),.number(w),.string(unit)])}
                return output("up",["weight":.number(up),"reps":.number(r.bottom)],[.string(facts.assisted ? "Top of the rep range in every set. {0} {1} less help, back to {2} reps." : "Top of the rep range in every set. {0} {1} more, back to {2} reps."),.number(owned == nil ? step : TrainingMath.jsRound((up-w)*100)/100),.string(unit),.number(r.bottom)])
            }
            if count>=deloadAt {if let chosen=epleyDeload() {return chosen};let dw=easier(w);return output("deload",["weight":.number(dw),"reps":.number(r.bottom)],[.string(facts.assisted ? "Stuck for {0} sessions. Back to {1} {2} of help, then build up again." : "Stuck for {0} sessions. Deload to {1} {2}."),.number(Double(count)),.number(dw),.string(unit)])}
            let aim=min(r.top,max(r.bottom,last.number("low")+stride));return output("hold",["weight":.number(w),"reps":.number(aim)],[.string("Same weight, aim for {0} reps this time."),.number(aim)])
        }
        if last.flag("ok") {
            let doubled=policy=="greyskull" && last.number("goal")>0 && last.number("amrap")>=last.number("goal")*2,up=harder(w,doubled)
            if owned != nil && up==w {return output("hold",["weight":.number(w)],[.string("You’ve outgrown the rack: {0} {1} is your heaviest dumbbell, so the weight stays."),.number(w),.string(unit)])}
            let by=owned == nil ? doubled ? step*2 : step : TrainingMath.jsRound((up-w)*100)/100
            let why:[JSONValue]=doubled ? [.string("Last set hit {0} reps, twice the target! Take a double jump of {1} {2}."),.number(last.number("amrap")),.number(by),.string(unit)] : [.string(facts.assisted ? "Every rep last time. {0} {1} less help." : "Every rep last time. {0} {1} more."),.number(by),.string(unit)]
            return output("up",["weight":.number(up)],why)
        }
        if count>=deloadAt {if let chosen=epleyDeload() {return chosen};let dw=easier(w);let why:[JSONValue]=facts.assisted ? [.string("Missed reps. {0} {1} of help while you build back up."),.number(dw),.string(unit)] : count>1 ? [.string("Missed reps {0} sessions running. Reset to {1} {2} and work back up."),.number(Double(count)),.number(dw),.string(unit)] : [.string("Missed reps. Reset to {0} {1} and work back up."),.number(dw),.string(unit)];return output("deload",["weight":.number(dw)],why)}
        return output("hold",["weight":.number(w)],[.string("Missed reps last time. Same weight again ({0} of {1} to go)."),.number(Double(deloadAt-count)),.number(Double(deloadAt))])
    }
}
