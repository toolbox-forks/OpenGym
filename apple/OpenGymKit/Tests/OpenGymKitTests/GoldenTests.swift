import Foundation
import XCTest
@testable import OpenGymKit

struct GoldenCase: Codable { let kind: String; let input: JSONValue; let expected: JSONValue }
final class GoldenTests: XCTestCase {
    func cases(_ kind: String) throws -> [GoldenCase] {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"golden",withExtension:"json"))
        let all=try JSONDecoder().decode([GoldenCase].self,from:Data(contentsOf:url))
        XCTAssertGreaterThan(all.count,1000,"The shared production fixture corpus must execute")
        let selected=all.filter {$0.kind==kind}; XCTAssertFalse(selected.isEmpty)
        return selected
    }
    func testOneRMMatchesProductionJS() throws {
        for c in try cases("oneRM") {
            let x=c.input
            let result=TrainingMath.oneRM(weight:x.number("w"),reps:x.number("r"),formula:x.text("formula"),rir:x["rir"].doubleValue)
            if let expected=c.expected.doubleValue { XCTAssertEqual(try XCTUnwrap(result),expected,accuracy:1e-8,"\(x)") }
            else { XCTAssertNil(result,"\(x)") }
        }
    }
    func testUnitsMatchProductionJS() throws {
        for kind in ["units","bodyUnits"] {
            for c in try cases(kind) {
                let x=c.input, from=try XCTUnwrap(TrainingMath.Unit(rawValue:x.text("from"))), to=try XCTUnwrap(TrainingMath.Unit(rawValue:x.text("to")))
                let value=kind=="units" ? TrainingMath.convertWeight(x.number("w"),from:from,to:to) : TrainingMath.convertBodyWeight(x.number("w"),from:from,to:to)
                XCTAssertEqual(value,try XCTUnwrap(c.expected.doubleValue),accuracy:1e-9)
            }
        }
    }
    func testPlateStackMatchesProductionJS() throws {
        for c in try cases("plates") {
            let result=PlateLoading.stack(weight:c.input.number("w"),inventory:c.input.rows("inventory").map {Plate(w:$0.number("w"),n:Int($0.number("n")))})
            XCTAssertEqual(result.plates,c.expected.rows("plates").compactMap(\.doubleValue))
            XCTAssertEqual(result.missing,c.expected.number("missing"),accuracy:1e-9)
        }
    }
    func testWarmupsMatchProductionJS() throws {
        for c in try cases("warmups") {
            let x=c.input
            XCTAssertEqual(TrainingMath.warmups(weight:x.number("weight"),count:Int(x.number("count")),step:x.number("step"),floor:x.number("floor")),c.expected.arrayValue.compactMap(\.doubleValue))
        }
    }
    func testSessionReadbackMatchesProductionJS() throws {
        for c in try cases("readSession") {
            let facts=try JSONDecoder().decode(ExerciseFacts.self,from:JSONEncoder().encode(c.input["facts"]))
            XCTAssertEqual(Progression.readSession(entry:c.input["entry"],fallback:c.input["fallback"],facts:facts),c.expected,"\(c.input)")
        }
    }
    func testProgressionTargetsAndReasonsMatchProductionJS() throws {
        for c in try cases("progression") {
            let facts=try JSONDecoder().decode(ExerciseFacts.self,from:JSONEncoder().encode(c.input["facts"]))
            XCTAssertEqual(Progression.next(state:c.input["state"],cfg:c.input["cfg"],routine:c.input["routine"],facts:facts),c.expected,"\(c.input)")
        }
    }
    func testInvalidMathDoesNotProduceInventedPRs() {
        XCTAssertNil(TrainingMath.oneRM(weight:.nan,reps:5))
        XCTAssertNil(TrainingMath.oneRM(weight:60,reps:.infinity))
        XCTAssertNil(TrainingMath.oneRM(weight:-1,reps:5))
    }
}
