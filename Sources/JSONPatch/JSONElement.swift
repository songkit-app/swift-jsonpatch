//
//  JSONElement.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// JSON Element holds a reference an element of the parsed JSON structure
/// produced by JSONSerialization.
enum JSONElement {
    case object(value: NSDictionary)
    case mutableObject(value: NSMutableDictionary)
    case array(value: NSArray)
    case mutableArray(value: NSMutableArray)
    case string(value: NSString)
    case number(value: NSNumber)
    case null
}

extension JSONElement {

    /// The raw value of the underlying JSON representation.
    var rawValue: Any {
        switch self {
        case .object(let value):
            return value
        case .mutableObject(let value):
            return value
        case .array(let value):
            return value
        case .mutableArray(let value):
            return value
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .null:
            return NSNull()
        }
    }

    /// Indicates if the receiver is a mutable container (dictionary or array).
    var isMutable: Bool {
        switch self {
        case .mutableObject, .mutableArray:
            return true
        case .object, .array, .string, .number, .null:
            return false
        }
    }

    init(any: Any) throws {
        switch any {
        case let dict as NSMutableDictionary:
            self = .mutableObject(value: dict)
        case let dict as NSDictionary:
            self = .object(value: dict)
        case let array as NSMutableArray:
            self = .mutableArray(value: array)
        case let array as NSArray:
            self = .array(value: array)
        case let str as NSString:
            self = .string(value: str)
        case let num as NSNumber:
            self = .number(value: num)
        case is NSNull:
            self = .null
        default:
            throw JSONError.invalidObjectType
        }
    }

    /// Creates a new JSONElement with a copied raw value of the reciever.
    ///
    /// - Returns: A JSONElement representing a copy of the reciever.
    private func copy() -> JSONElement {
        switch rawValue {
        case let dict as NSDictionary:
            return try! JSONElement(any: dict.deepMutableCopy())
        case let arr as NSArray:
            return try! JSONElement(any: arr.deepMutableCopy())
        case let null as NSNull:
            return try! JSONElement(any: null)
        case let obj as NSObject:
            return try! JSONElement(any: obj.mutableCopy())
        default:
            fatalError("JSONElement contained non-NSObject")
        }
    }

    private mutating func makeMutable() {
        switch self {
        case .object(let dictionary):
            let mutable = NSMutableDictionary(dictionary: dictionary)
            self = .mutableObject(value: mutable)
        case .array(let array):
            let mutable = NSMutableArray(array: array)
            self = .mutableArray(value: mutable)
        case .mutableObject, .mutableArray:
            break
        case .string, .number, .null:
            assertionFailure("Unsupported type to make mutable")
            break
        }
    }

    private mutating func makePathMutable(_ pointer: JSONPointer) throws -> JSONElement {
        if !self.isMutable {
            self.makeMutable()
        }

        guard pointer.string != "/" else {
            return self
        }

        var element = self
        for component in pointer.components {
            var child = try element.value(for: component)
            if !child.isMutable {
                child.makeMutable()
                try element.setValue(child, component: component, replace: true)
            }
            element = child
        }

        return element
    }

    /// This method is used to evalute a single component of a JSON Pointer.
    /// If the receiver represents a container (dictionary or array) with the JSON
    /// structure, then this method will get the value within the container referenced
    /// by the component of the JSON Pointer. If the receiver does not represent a
    /// container then an error is thrown.
    ///
    /// - Parameters:
    ///   - component: A single component of a JSON Pointer to evaluate.
    /// - Returns: The referenced value.
    private func value(for component: String) throws -> JSONElement {
        switch self {
        case .object(let dictionary), .mutableObject(let dictionary as NSDictionary):
            guard let property = dictionary[component] else {
                throw JSONError.referencesNonexistentValue
            }
            let child = try JSONElement(any: property)
            return child

        case .array(let array) where component == "-",
             .mutableArray(let array as NSArray) where component == "-":
            guard let lastElement = array.lastObject else {
                throw JSONError.referencesNonexistentValue
            }
            let child = try JSONElement(any: lastElement)
            return child

        case .array(let array), .mutableArray(let array as NSArray):
            guard
                JSONPointer.isValidArrayIndex(component),
                let index = Int(component),
                0..<array.count ~= index else {
                    throw JSONError.referencesNonexistentValue

            }
            let element = array[index]
            let child = try JSONElement(any: element)
            return child

        case .string, .number, .null:
            throw JSONError.referencesNonexistentValue
        }
    }

    private mutating func setValue(_ value: JSONElement, component: String, replace: Bool) throws {
        switch self {
        case .mutableObject(let dictionary):
            dictionary[component] = value.rawValue
        case .mutableArray(let array):
            if component == "-" {
                if replace && array.count > 0 {
                    array.replaceObject(at: array.count - 1, with: value.rawValue)
                } else {
                    array.add(value.rawValue)
                }
            } else {
                guard
                    JSONPointer.isValidArrayIndex(component),
                    let index = Int(component),
                    0...array.count ~= index else {
                        throw JSONError.referencesNonexistentValue

                }
                if replace {
                    array.replaceObject(at: index, with: value.rawValue)
                } else {
                    array.insert(value.rawValue, at: index)
                }
            }
        default:
            break
        }
    }

    private mutating func removeValue(component: String) throws {
        switch self {
        case .mutableObject(let dictionary):
            guard dictionary[component] != nil else {
                throw JSONError.referencesNonexistentValue
            }
            dictionary.removeObject(forKey: component)
        case .mutableArray(let array):
            if component == "-" {
                guard array.count > 0 else {
                    throw JSONError.referencesNonexistentValue
                }
                array.removeLastObject()
            } else {
                guard
                    JSONPointer.isValidArrayIndex(component),
                    let index = Int(component),
                    0..<array.count ~= index else {
                        throw JSONError.referencesNonexistentValue

                }
                array.removeObject(at: index)
            }
        default:
            break
        }
    }

    /// Evaluates a JSON Pointer relative to the receiver JSON Element.
    ///
    /// - Parameters:
    ///   - pointer: The JSON Pointer to evaluate.
    /// - Returns: The JSON Element pointed to by the JSON Pointer
    func evaluate(pointer: JSONPointer) throws -> JSONElement {
        return try pointer.components.reduce(self, { return try $0.value(for: $1) })
    }

    /// Adds the value to the JSON structure pointed to by the JSON Pointer.
    ///
    /// - Parameters:
    ///   - value: A JSON Element holding a reference to the value to add.
    ///   - pointer: A JSON Pointer of the location to insert the value.
    mutating func add(value: JSONElement, to pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = value
            return
        }

        var parentElement = try makePathMutable(parent)
        try parentElement.setValue(value, component: pointer.components.last!, replace: false)
    }

    /// Removes a value from a JSON structure pointed to by the JSON Pointer.
    ///
    /// - Parameters:
    ///   - pointer: A JSON Pointer of the location of the value to remove.
    mutating func remove(at pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = .null
            return
        }

        var parentElement = try makePathMutable(parent)
        try parentElement.removeValue(component: pointer.components.last!)
    }

    /// Replaces a value at the location pointed to by the JSON Pointer with
    /// the given value. There must be an existing value to replace for this
    /// operation to be successful.
    ///
    /// - Parameters:
    ///   - value: A JSON Element holding a reference to the value to add.
    ///   - pointer: A JSON Pointer of the location of the value to replace.
    mutating func replace(value: JSONElement, to pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = value
            return
        }

        var parentElement = try makePathMutable(parent)
        _ = try parentElement.value(for: pointer.components.last!)
        try parentElement.setValue(value, component: pointer.components.last!, replace: true)
    }

    /// Moves a value at the from location to a new location within the JSON Structure.
    ///
    /// - Parameters:
    ///   - from: The location of the JSON element to move.
    ///   - to: The location to move the value to.
    mutating func move(from: JSONPointer, to: JSONPointer) throws {
        guard let toParent = to.parent else {
            self = try evaluate(pointer: from)
            return
        }

        guard let fromParent = from.parent else {
            throw JSONError.referencesNonexistentValue
        }

        var fromParentElement = try  makePathMutable(fromParent)
        let value = try fromParentElement.value(for: from.components.last!)
        try fromParentElement.removeValue(component: from.components.last!)

        var toParentElement = try makePathMutable(toParent)
        try toParentElement.setValue(value, component: to.components.last!, replace: false)
    }

    /// Copies a JSON element within the JSON structure to a new location.
    ///
    /// - Parameters:
    ///   - from: The location of the value to copy.
    ///   - to: The location to insert the new value.
    mutating func copy(from: JSONPointer, to: JSONPointer) throws {
        guard let toParent = to.parent else {
            self = try evaluate(pointer: from)
            return
        }

        guard let fromParent = from.parent else {
            throw JSONError.referencesNonexistentValue
        }

        let fromParentElement = try makePathMutable(fromParent)
        var toParentElement = try makePathMutable(toParent)
        let value = try fromParentElement.value(for: from.components.last!)
        let valueCopy = value.copy()
        try toParentElement.setValue(valueCopy, component: to.components.last!, replace: false)
    }

    /// Tests a value within the JSON structure against the given value.
    ///
    /// - Parameters:
    ///   - value: The expected value.
    ///   - pointer: The location of the value to test.
    func test(value: JSONElement, at pointer: JSONPointer) throws {
        do {
            let found = try evaluate(pointer: pointer)
            if found != value {
                throw JSONError.patchTestFailed(path: pointer.string,
                                                expected: value.rawValue,
                                                found: found.rawValue)
            }
        } catch {
            throw JSONError.patchTestFailed(path: pointer.string,
                                            expected: value.rawValue,
                                            found: nil)
        }
    }

    /// Applies a json-patch operation to the reciever.
    ///
    /// - Parameters:
    ///   - operation: The operation to apply.
    mutating func apply(_ operation: JSONPatch.Operation) throws {
        switch operation {
        case let .add(path, value):
            try add(value: try JSONElement(any: value), to: path)
        case let .remove(path):
            try remove(at: path)
        case let .replace(path, value):
            try replace(value: try JSONElement(any: value), to: path)
        case let .move(from, path):
            try move(from: from, to: path)
        case let .copy(from, path):
            try copy(from: from, to: path)
        case let .test(path, value):
            try test(value: try JSONElement(any: value), at: path)
        }
    }

    mutating func apply(patch: JSONPatch) throws {
        for operation in patch.operations {
            try apply(operation)
        }
    }

}

extension JSONElement: Equatable {

    /// Tests if two JSON Elements are structurally.
    ///
    /// - Parameters:
    ///   - lhs: Left-hand side of the equality test.
    ///   - rhs: Right-hand side of the equality test.
    /// - Returns: true if lhs and rhs are structurally, otherwise false.
    static func == (lhs: JSONElement, rhs: JSONElement) -> Bool {
        guard let lobj = lhs.rawValue as? JSONEquatable else {
            return false
        }
        return lobj.isJSONEquals(to: rhs)
    }

}

extension JSONSerialization {

    /// Generate JSON data from a JSONElement using JSONSerialization. This method supports
    /// top-level fragments (root elements that are not containers).
    ///
    /// - Parameters:
    ///   - jsonElement: The top-level json element to generate data for.
    ///   - options: The wripting options for generating the json data.
    /// - Returns: A UTF-8 represention of the json document with the jsonElement as the root.
    static func data(with jsonElement: JSONElement, options: WritingOptions = []) throws -> Data {
        // JSONSerialization only supports writing top-level containers.
        switch jsonElement {
        case let .object(obj as NSObject),
             let .mutableObject(obj as NSObject),
             let .array(obj as NSObject),
             let .mutableArray(obj as NSObject):
            return try JSONSerialization.data(withJSONObject: obj, options: options)
        default:
            // If the element is not a container then wrap the element in an array and the
            // return the sub-sequence of the result that represents the original element.
            let array = [jsonElement.rawValue]
            // We ignore the passed in writing options for this case, as it only effects
            // containers and could cause indexes to shift.
            let data = try JSONSerialization.data(withJSONObject: array, options: [])
            guard let arrayEndRange = data.range(of: Data("]".utf8),
                                                 options: [.backwards],
                                                 in: nil) else {
                                                    throw JSONError.invalidObjectType
            }
            let subdata = data.subdata(in: data.index(after: data.startIndex)..<arrayEndRange.startIndex)
            return subdata
        }
    }

}
