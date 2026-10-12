import Foundation

public enum TrainingMath {
    // Match Math.round (ties toward +infinity), not Swift's negative tie behaviour.
    public static func jsRound(_ value: Double) -> Double { floor(value + 0.5) }
    public static func round1(_ value: Double) -> Double { jsRound(value * 10) / 10 }
    public static func snap(_ value: Double, step: Double) -> Double {
        step > 0 ? round1(jsRound(value / step) * step) : round1(value)
    }
    public static func addStep(_ weight: Double, by change: Double, increment: Double) -> Double {
        let onGrid = increment > 0 && abs(weight - jsRound(weight / increment) * increment) <= 0.1
        return max(0, onGrid ? snap(weight + change, step: increment) : round1(weight + change))
    }
    public static func oneRM(weight: Double, reps: Double, formula: String = "epley", rir: Double? = nil) -> Double? {
        guard weight.isFinite, reps.isFinite, weight > 0, reps >= 1 else { return nil }
        let validRIR = rir.map { $0 >= 0 } ?? false
        if reps == 1 && (!validRIR || rir == 0) { return round1(weight) }
        let result: Double
        if formula == "weighted" {
            let effective = validRIR ? reps + (rir ?? 0) : reps
            guard effective <= 15 else { return nil }
            let coefficients: [(String, Double, Double, Double, Double)] = [
                ("epley",0.95,6,0.4,0.12),("brzycki",1.10,8,0.3,0.18),
                ("lombardi",0.85,5,0.4,0.10),("oconner",0.90,6,0.4,0.12),
                ("mayhew",0.95,8,0.5,0.10),("wathan",0.90,7,0.4,0.12),
                ("lander",0.85,7,0.35,0.15)
            ]
            var total = 0.0, sum = 0.0
            for (name, reliability, threshold, minimum, fall) in coefficients {
                let factor = reliability * (effective <= threshold ? 1 : max(minimum,1-(effective-threshold)*fall))
                total += estimate(weight, effective, name) * factor; sum += factor
            }
            let percentages = [100.0,95.5,92.2,89.2,86.3,83.7,81.1,78.6,76.2,73.9,71.7,69.5,67.5,65.5,63.6]
            let i = min(14,max(0,Int(jsRound(effective))-1))
            let factor = effective <= 10 ? 1 : max(0.4,1-(effective-10)*0.15)
            result = (total + weight*100/percentages[i]*factor) / (sum+factor)
        } else {
            guard reps <= 12 else { return nil }
            result = reps == 1 ? weight : estimate(weight,jsRound(reps),formula)
        }
        guard result.isFinite, result > 0 else { return nil }
        return round1(result)
    }
    private static func estimate(_ w: Double, _ r: Double, _ f: String) -> Double {
        switch f {
        case "brzycki": return w*36/(37-r)
        case "lombardi": return w*pow(r,0.1)
        case "oconner": return w*(1+r/40)
        case "mayhew": return w*100/(52.2+41.9*exp(-0.055*r))
        case "wathan": return w*100/(48.8+53.8*exp(-0.075*r))
        case "lander": return w*100/(101.3-2.67123*r)
        default: return w*(1+r/30)
        }
    }
    public enum Unit: String, Codable, Sendable { case kg, lb }
    public static let poundsPerKilogram = 2.2046226218
    public static func convertWeight(_ value: Double, from: Unit, to: Unit) -> Double {
        guard from != to, value.isFinite else { return value }
        return to == .lb ? jsRound(value*poundsPerKilogram*2)/2 : jsRound(value/poundsPerKilogram*4)/4
    }
    public static func convertBodyWeight(_ value: Double, from: Unit, to: Unit) -> Double {
        guard from != to, value.isFinite else { return value }
        return jsRound((to == .lb ? value*poundsPerKilogram : value/poundsPerKilogram)*10)/10
    }
    /// Same halving ramp as history.insertWarmupRow; no warm-up exceeds the work load.
    public static func warmups(weight: Double, count: Int, step: Double = 2.5, floor bar: Double = 0, owned: [Double]? = nil) -> [Double] {
        guard weight.isFinite, step.isFinite, step > 0 else { return [] }
        var previous = 0.0, result: [Double] = []
        for _ in 0..<max(0,min(5,count)) {
            let ideal = previous + (weight-previous)/2
            let snapped = owned.map { values in values.filter { $0 <= ideal+1e-9 && $0.isFinite }.max() ?? values.first ?? 0 } ?? floor(ideal/step)*step
            let next = weight <= 0 ? 0 : weight <= previous ? weight : min(weight,max(0,max(bar,snapped)))
            result.append(next); previous = next
        }
        return result
    }
}

public struct Plate: Codable, Equatable, Sendable {
    public let w: Double
    public let n: Int
    public init(w: Double, n: Int) { self.w=w; self.n=n }
}
public struct PlateResult: Codable, Equatable, Sendable {
    public let plates: [Double]
    public let missing: Double
}
public enum PlateLoading {
    public static func stack(weight: Double, inventory: [Plate]) -> PlateResult {
        guard weight.isFinite else { return PlateResult(plates: [], missing: 0) }
        let requested=max(0,weight), target=Int(floor(requested*4))
        guard target > 0 else { return PlateResult(plates: [], missing: requested) }
        let items=inventory.filter { $0.w.isFinite && $0.w>0 && $0.n>0 && TrainingMath.jsRound($0.w*4)>0 }.sorted { $0.w>$1.w }
        var left=target, greedy:[Double]=[]
        for p in items {
            let size=Int(TrainingMath.jsRound(p.w*4)), count=min(p.n,left/size)
            greedy.append(contentsOf: Array(repeating:p.w,count:count)); left -= size*count
        }
        let all=items.reduce(0) { $0+Int(TrainingMath.jsRound($1.w*4))*$1.n }
        if left==0 || target>=all { return PlateResult(plates:greedy,missing:requested-Double(target-left)/4) }
        // Bound allocation to what exists; large typo loads take the greedy/all-inventory path.
        let infinity=1_000_000_000
        var table=Array(repeating:Array(repeating:infinity,count:target+1),count:items.count+1)
        table[items.count][0]=0
        for i in stride(from:items.count-1,through:0,by:-1) {
            let size=Int(TrainingMath.jsRound(items[i].w*4))
            for sum in 0...target {
                var best=table[i+1][sum]
                for k in 0...min(items[i].n,sum/size) { best=min(best,table[i+1][sum-k*size]+k) }
                table[i][sum]=best
            }
        }
        var reachable=target
        while reachable>0 && table[0][reachable]>=infinity { reachable-=1 }
        var remainder=reachable, result:[Double]=[]
        for i in items.indices {
            let size=Int(TrainingMath.jsRound(items[i].w*4))
            for k in stride(from:min(items[i].n,remainder/size),through:0,by:-1) {
                if table[i+1][remainder-k*size]+k == table[i][remainder] {
                    result.append(contentsOf:Array(repeating:items[i].w,count:k)); remainder-=k*size; break
                }
            }
        }
        return PlateResult(plates:result,missing:requested-Double(reachable)/4)
    }
}
