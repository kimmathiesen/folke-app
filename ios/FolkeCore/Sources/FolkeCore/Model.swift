import CoreData
import Foundation

// Core Data-modellen (ios/PLAN.md afsnit 2), bygget i kode, så den kan deles med widgets og App Intents.
// Krav fra CloudKit: alle attributter valgfri eller med standardværdi, ingen unikke constraints,
// alle relationer valgfri og med inverse. `id` (UUID) er det stabile id.
// Version 2: en familie over børnene. Familien deles (milepæl 6), så alt under den ligger i samme CloudKit-zone.
// Søvn, mad, vækst og forslag hænger på barnet; udpumpning og tavlen på familien (de er forældrenes, ikke barnets).
// Tal, der kan mangle (ml, minutter, mål), gemmes som 0 = ikke angivet.
// `serverID` er id'et fra Folke-serveren ved import (0 = oprettet i appen), så gentaget import ikke giver dubletter.

/// Familien: børnene, udpumpning, tavlen og de fælles valg for udpumpning.
@objc(FKFamily) public final class Family: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var featurePump: Bool
    @NSManaged public var pumpRemindHours: Double
    @NSManaged public var children: Set<Child>?
    @NSManaged public var pumpings: Set<Pumping>?
    @NSManaged public var strokes: Set<Stroke>?
}

@objc(FKChild) public final class Child: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var birthDate: Date?
    /// "boy" eller "girl" (vækstkurver)
    @NSManaged public var sex: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var sleeps: Set<Sleep>?
    @NSManaged public var feedings: Set<Feeding>?
    @NSManaged public var pumpings: Set<Pumping>?
    @NSManaged public var growths: Set<Growth>?
    @NSManaged public var strokes: Set<Stroke>?
    @NSManaged public var settings: Set<Settings>?
    @NSManaged public var family: Family?
}

@objc(FKSleep) public final class Sleep: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var start: Date?
    /// nil = søvnen er i gang (erstatter serverens «timer»)
    @NSManaged public var end: Date?
    @NSManaged public var nap: Bool
    /// "mor" eller "far"
    @NSManaged public var createdBy: String?
    @NSManaged public var serverID: Int64
    @NSManaged public var child: Child?
}

@objc(FKFeeding) public final class Feeding: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var time: Date?
    /// left, right, both, bottle eller solid
    @NSManaged public var kind: String?
    @NSManaged public var amountMl: Double
    /// breast eller formula (flaske)
    @NSManaged public var milk: String?
    @NSManaged public var note: String?
    @NSManaged public var serverID: Int64
    @NSManaged public var child: Child?
}

@objc(FKPumping) public final class Pumping: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var time: Date?
    @NSManaged public var amountMl: Double
    /// left, right, both eller nil
    @NSManaged public var side: String?
    @NSManaged public var minutes: Double
    @NSManaged public var serverID: Int64
    /// Kun version 1 (før familien); flyttes til `family` ved opgraderingen
    @NSManaged public var child: Child?
    @NSManaged public var family: Family?
}

@objc(FKGrowth) public final class Growth: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var weightKg: Double
    @NSManaged public var lengthCm: Double
    @NSManaged public var headCm: Double
    @NSManaged public var serverID: Int64
    @NSManaged public var child: Child?
}

/// Tavlen: én post pr. streg, så to forældre aldrig skriver i samme post.
@objc(FKStroke) public final class Stroke: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var color: String?
    @NSManaged public var width: Double
    /// [x, y] som Float32 i 0..1
    @NSManaged public var points: Data?
    @NSManaged public var createdAt: Date?
    @NSManaged public var createdBy: String?
    /// Kun version 1 (før familien); flyttes til `family` ved opgraderingen
    @NSManaged public var child: Child?
    @NSManaged public var family: Family?
}

/// Indstillinger for ét barn (amning, fast føde, forudsigelse, svar på forslag).
/// Udpumpning ligger på familien; `featurePump` og `pumpRemindHours` her er kun version 1.
@objc(FKSettings) public final class Settings: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var featureBreast: Bool
    @NSManaged public var featureSolids: Bool
    @NSManaged public var featurePump: Bool
    @NSManaged public var pumpRemindHours: Double
    /// JSON: [Suggestions.ID: Suggestions.Stored]
    @NSManaged public var suggestionAnswers: Data?
    /// Forudsigelsen kan skjules, når barnet er holdt op med at sove lur (ca. 3 år)
    @NSManaged public var featurePrediction: Bool
    @NSManaged public var child: Child?
}

public enum FolkeModel {
    /// Én fælles instans: flere modeller med de samme klasser giver advarsler fra Core Data.
    nonisolated(unsafe) public static let shared: NSManagedObjectModel = build(version: current)
    public static let current = 2

    /// `version` 1 er modellen før familien (bruges kun til at opgradere gamle databaser). Den bygges uden
    /// klasser, så kun den aktuelle model gør krav på FK-klasserne.
    static func build(version: Int) -> NSManagedObjectModel {
        let v2 = version >= 2
        func attr(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            a.defaultValue = value
            return a
        }
        func entity<T: NSManagedObject>(_ cls: T.Type, _ attrs: [NSAttributeDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = String(describing: cls)
            e.managedObjectClassName = v2 ? NSStringFromClass(cls) : "NSManagedObject"
            e.properties = attrs
            return e
        }
        let id = { attr("id", .UUIDAttributeType) }
        let serverID = { attr("serverID", .integer64AttributeType, default: 0) }

        let child = entity(Child.self, [
            id(), attr("name", .stringAttributeType), attr("birthDate", .dateAttributeType),
            attr("sex", .stringAttributeType, default: "boy"), attr("createdAt", .dateAttributeType),
        ])
        let sleep = entity(Sleep.self, [
            id(), attr("start", .dateAttributeType), attr("end", .dateAttributeType),
            attr("nap", .booleanAttributeType, default: true), attr("createdBy", .stringAttributeType), serverID(),
        ])
        let feeding = entity(Feeding.self, [
            id(), attr("time", .dateAttributeType), attr("kind", .stringAttributeType),
            attr("amountMl", .doubleAttributeType, default: 0), attr("milk", .stringAttributeType),
            attr("note", .stringAttributeType), serverID(),
        ])
        let pumping = entity(Pumping.self, [
            id(), attr("time", .dateAttributeType), attr("amountMl", .doubleAttributeType, default: 0),
            attr("side", .stringAttributeType), attr("minutes", .doubleAttributeType, default: 0), serverID(),
        ])
        let growth = entity(Growth.self, [
            id(), attr("date", .dateAttributeType), attr("weightKg", .doubleAttributeType, default: 0),
            attr("lengthCm", .doubleAttributeType, default: 0), attr("headCm", .doubleAttributeType, default: 0),
            serverID(),
        ])
        let stroke = entity(Stroke.self, [
            id(), attr("color", .stringAttributeType), attr("width", .doubleAttributeType, default: 0),
            attr("points", .binaryDataAttributeType), attr("createdAt", .dateAttributeType),
            attr("createdBy", .stringAttributeType),
        ])
        let settings = entity(Settings.self, [
            id(), attr("createdAt", .dateAttributeType),
            attr("featureBreast", .booleanAttributeType, default: true),
            attr("featureSolids", .booleanAttributeType, default: false),
            attr("featurePump", .booleanAttributeType, default: true),
            attr("pumpRemindHours", .doubleAttributeType, default: 3.0),
            attr("suggestionAnswers", .binaryDataAttributeType),
        ] + (v2 ? [attr("featurePrediction", .booleanAttributeType, default: true)] : []))

        // En-til-mange med invers. Alle relationer er valgfrie (CloudKit).
        func relate(_ owner: NSEntityDescription, _ many: String, _ target: NSEntityDescription, _ one: String) {
            let m = NSRelationshipDescription()
            m.name = many
            m.destinationEntity = target
            m.minCount = 0
            m.maxCount = 0
            m.isOptional = true
            m.deleteRule = .cascadeDeleteRule

            let o = NSRelationshipDescription()
            o.name = one
            o.destinationEntity = owner
            o.minCount = 0
            o.maxCount = 1
            o.isOptional = true
            o.deleteRule = .nullifyDeleteRule

            m.inverseRelationship = o
            o.inverseRelationship = m
            owner.properties.append(m)
            target.properties.append(o)
        }
        for (target, name) in [(sleep, "sleeps"), (feeding, "feedings"), (pumping, "pumpings"),
                               (growth, "growths"), (stroke, "strokes"), (settings, "settings")] {
            relate(child, name, target, "child")
        }

        let model = NSManagedObjectModel()
        model.entities = [child, sleep, feeding, pumping, growth, stroke, settings]
        if v2 {
            let family = entity(Family.self, [
                id(), attr("createdAt", .dateAttributeType),
                attr("featurePump", .booleanAttributeType, default: true),
                attr("pumpRemindHours", .doubleAttributeType, default: 3.0),
            ])
            relate(family, "children", child, "family")
            relate(family, "pumpings", pumping, "family")
            relate(family, "strokes", stroke, "family")
            model.entities.append(family)
        }
        return model
    }
}

public extension Sleep {
    /// Som input til forudsigelsen (kun afsluttede søvn).
    var sample: SleepSample? {
        guard let id, let start, let end else { return nil }
        return SleepSample(id: id, start: start, end: end, nap: nap)
    }
}

public extension Settings {
    var answers: [Suggestions.ID: Suggestions.Stored] {
        get {
            guard let suggestionAnswers else { return [:] }
            return (try? JSONDecoder().decode([Suggestions.ID: Suggestions.Stored].self, from: suggestionAnswers)) ?? [:]
        }
        set { suggestionAnswers = try? JSONEncoder().encode(newValue) }
    }
}
