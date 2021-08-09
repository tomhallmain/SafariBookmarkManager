#!/usr/bin/env swift

import Foundation

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}




/// Not using below structs but keeping for documentation purposes 
/// as rough form of data contained in bookmarks plist

public struct URIDictionary: Codable {
    var title: String
}

public struct ReadingList: Codable {
    var DateAdded: Date
    var PreviewText: String
    var SourceBundleID: String
    var SourceLocalizedAppName: String
}

public struct ReadingListNonSync: Codable {
    var ArchiveOnDisk: Bool?
    var DateLastFetched: Date?
    var FetchResult: Int?
    var PreviewText: String
    var Title: String /// only applies to folders
    var didAttemptToFetchIconFromImageUrlKey: Bool?
    var neverFetchMetadata: Bool
    var siteName: String?
    var topicQIDs: [String]?
}

public struct Sync: Codable {
    var Data: Data
    var ServerID: String
}

public struct BookmarkListItem: Codable {
    var Children: [BookmarkListItem]?
    var ReadingList: ReadingList?
    var ShouldOmitFromUI: Bool?
    var Sync: Sync?
    var URIDictionary: URIDictionary?
    var URLString: String?
    var WebBookmarkAutoTab: Bool?
    var WebBookmarkType: String
    var WebBookmarkUUID: String
    var WebBookmarkFileVersion: String?
    var WebBookmarkIdentifier: String?
    var imageURL: String?
    var previewText: String?
    var previewTextIsUserDefined: Bool?
}

public struct MysteryData: Codable { /// Not sure where this data is but python claims it exists
    var CloudKitMigrationState: Int
    var CloudKitDeviceIdentifier: String
    var CloudKitAccountHash: Data
    var HomeURL: String
    var ServerData: Data
}




/// Functions


func errorQuit(errorText: String)
{
    print(errorText)
    exit(1)
}

func secureCopyItemAtPath(at srcPath: String, to dstPath: String) -> Bool
{
    do {
        if FileManager.default.fileExists(atPath: dstPath) {
            try FileManager.default.removeItem(atPath: dstPath)
        }
        try FileManager.default.copyItem(atPath: srcPath, toPath: dstPath)
    } catch (let error) {
        print("Cannot copy item at \(srcPath) to \(dstPath): \(error)")
        return false
    }
    return true
}

func getPlist(withPath path: String) -> Dictionary<String,Any>?
{
    if let xml = FileManager.default.contents(atPath: path)
    {
        do {
            return try PropertyListSerialization.propertyList(from: xml, options: .mutableContainersAndLeaves, format: nil) as? Dictionary<String,Any>
        } catch (let error) {
            print(error)
        }
    }

    return nil
}

func getItemTitle(withItem bookmarkItem: Dictionary<String,Any>) -> String?
{
    if bookmarkItem["URIDictionary"] != nil {
        let uriDict = bookmarkItem["URIDictionary"] as! Dictionary<String, String>
        if uriDict["title"] != nil {
            let title = uriDict["title"]!
            return title
        }
    }
    if bookmarkItem["Title"] != nil {
        let title = bookmarkItem["Title"] as! String
        return title
    }
    return nil
}

func itemIDInList(withList itemsList: Dictionary<String,Any>, withID id: String) -> Bool
{
    if itemsList["Children"] == nil {
        return false
    }
    if itemsList["WebBookmarkUUID"] != nil && (itemsList["WebBookmarkUUID"] as! String) == id {
        return true
    }
    let sublist = itemsList["Children"] as! [Dictionary<String,Any>]
    for item in sublist {
        if item["WebBookmarkUUID"] != nil && (item["WebBookmarkUUID"] as! String) == id {
            return true
        }
        else if itemIDInList(withList: item, withID: id) {
            return true
        }
    }
    return false
}

func getReadableFolderAddress(withList itemsList: Dictionary<String,Any>, withFolderID id: String, withSeed seed: String) -> String
{
    let tryTitle = getItemTitle(withItem: itemsList)
    var title = ""
    if tryTitle != nil {
        title = tryTitle!
    }
    let sublist = itemsList["Children"] as! [Dictionary<String,Any>]
    for item in sublist {
        if item["Children"] != nil {
            if itemIDInList(withList: item, withID: id) {
                if title != "" {
                    title += "."
                }
                return title + getReadableFolderAddress(withList: item, withFolderID: id, withSeed: seed)
            }
            else if item["WebBookmarkUUID"] != nil && (item["WebBookmarkUUID"] as! String) == id {
                let tryTitle = getItemTitle(withItem: itemsList)
                if tryTitle != nil {
                    print(tryTitle!)
                    return tryTitle!
                }
            }
        }
    }
    return title
}

func attrMatch(withItem bookmarkItem: Dictionary<String,Any>, withAttr attr: String, withPattern pattern: String) -> Bool
{
    let regex = try! NSRegularExpression(pattern: pattern)
    if attr == "title" {
        let tryTitle = getItemTitle(withItem: bookmarkItem)
        if tryTitle != nil {
            let title = tryTitle!
            let range = NSRange(location: 0, length: title.utf16.count)
            return regex.firstMatch(in: title, options: [], range: range) != nil
        }
    }
    else if bookmarkItem[attr] != nil {
        let attrVal = bookmarkItem[attr] as! String
        if attr == "WebBookmarkType" || attr == "WebBookmarkUUID" {
            return attrVal == pattern
        }
        else {
            let range = NSRange(location: 0, length: attrVal.utf16.count)
            return regex.firstMatch(in: attrVal, options: [], range: range) != nil
        }
    }
    return false
}

func matchesBookmarkItem(withItem1 bookmarkItem1: Dictionary<String,Any>, withItem2 bookmarkItem2: Dictionary<String,Any>) -> Bool
{
    if bookmarkItem1["WebBookmarkUUID"] == nil && bookmarkItem1["WebBookmarkUUID"] != nil {
        return false
    }
    else if bookmarkItem1["WebBookmarkUUID"] != nil && bookmarkItem1["WebBookmarkUUID"] == nil {
        return false
    }
    let id1 = bookmarkItem1["WebBookmarkUUID"] as! String
    let id2 = bookmarkItem2["WebBookmarkUUID"] as! String
    return id1 == id2
}

func containsBookmarkItem(withList itemsList: [Dictionary<String,Any>], withItem testItem: Dictionary<String,Any>) -> Bool
{
    for item in itemsList {
        if matchesBookmarkItem(withItem1: item, withItem2: testItem) {
            return true
        }
    }
    return false
}

func getBookmarkItems(withList sublist: [Dictionary<String,Any>],
                      withAttr attr: String,
                      withPattern pattern: String,
                      withSeedList seedList: [Dictionary<String,Any>]) -> [Dictionary<String,Any>]
{
    var matchingItems = seedList
    for item in sublist {
        if item["Children"] != nil {
            matchingItems += getBookmarkItems(withList: item["Children"] as! [Dictionary<String, Any>],
                                              withAttr: attr,
                                              withPattern: pattern,
                                              withSeedList: seedList)
        }
        else if attrMatch(withItem: item, withAttr: attr, withPattern: pattern) {
            matchingItems.append(item)
        }
    }
    return matchingItems
}

func moveRecursive(withList sublist: [Dictionary<String,Any>],
                   withItem item: Dictionary<String,Any>, 
                   withItemID itemID: String,
                   withDestID destID: String) -> [Dictionary<String,Any>]
{
    var mutlist = sublist
    var i = 0
    while i < mutlist.count {
        if mutlist[i]["Children"] != nil {
            let isDest = attrMatch(withItem: mutlist[i], withAttr: "WebBookmarkUUID", withPattern: destID)
            var childrenMutList = moveRecursive(withList: mutlist[i]["Children"] as! [Dictionary<String, Any>], 
                                                withItem: item,
                                                withItemID: itemID,
                                                withDestID: destID)
            if isDest {
                childrenMutList.append(item)
                let title = getItemTitle(withItem: mutlist[i])
                if title != nil {
                    print("Adding bookmark with title: " + title! + " to destination folder")
                }
            }
            mutlist[i]["Children"] = childrenMutList
        }
        else if attrMatch(withItem: mutlist[i], withAttr: "WebBookmarkUUID", withPattern: itemID) {
            let title = getItemTitle(withItem: mutlist[i])
            if title != nil {
                print("Removing bookmark with title: " + title! + " from source folder")
            }
            mutlist.remove(at: i)
            continue
        }
        i += 1
    }
    return mutlist
}

func removeRecursive(withList sublist: [Dictionary<String,Any>], 
                     withAttr attr: String, 
                     withPattern pattern: String) -> [Dictionary<String,Any>]
{
    var mutlist = sublist
    var i = 0
    while i < mutlist.count {
        if mutlist[i]["Children"] != nil {
            mutlist[i]["Children"] = removeRecursive(withList: mutlist[i]["Children"] as! [Dictionary<String, Any>], withAttr: attr, withPattern: pattern)
        }
        else if attrMatch(withItem: mutlist[i], withAttr: attr, withPattern: pattern) {
            let title = getItemTitle(withItem: mutlist[i])
            if title != nil {
                print("Removing bookmark with title: " + title!)
            }
            mutlist.remove(at: i)
            continue
        }
        i += 1
    }
    return mutlist
}

func removeBookmarksByAttrPattern(withPlist bookmarksPlist: Dictionary<String,Any>, 
                                  withAttr attr: String, 
                                  withPattern pattern: String) throws -> Dictionary<String,Any>
{
    if pattern == "" {
        throw "Removal pattern is empty"
    }

    var mutPlist = bookmarksPlist
    let initialList = bookmarksPlist["Children"] as! [Dictionary<String,Any>]
    mutPlist["Children"] = removeRecursive(withList: initialList, withAttr: attr, withPattern: pattern)
    return mutPlist
}

func removeBookmarksByUrl(withPlist bookmarksPlist: Dictionary<String,Any>, withPattern pattern: String) throws -> Dictionary<String,Any> {
    return try removeBookmarksByAttrPattern(withPlist: bookmarksPlist, withAttr: "URLString", withPattern: pattern)
}

func removeBookmarksByTitle(withPlist bookmarksPlist: Dictionary<String,Any>, withPattern pattern: String) throws -> Dictionary<String,Any> {
    return try removeBookmarksByAttrPattern(withPlist: bookmarksPlist, withAttr: "title", withPattern: pattern)
}

func removeBookmarksByUrlOrTitle(withPlist bookmarksPlist: Dictionary<String,Any>, withPattern pattern: String) throws -> Dictionary<String,Any> {
    let mutPlist = try removeBookmarksByUrl(withPlist: bookmarksPlist, withPattern: pattern)
    return try removeBookmarksByTitle(withPlist: mutPlist, withPattern: pattern)
}

func getFolderIDsByTitleRecursive(withList sublist: [Dictionary<String,Any>], withTitle title: String, withIDs IDs: [String]) -> [String]
{
    var idsList = [String]()
    for item in sublist {
        if item["WebBookmarkUUID"] != nil && item["Children"] != nil {
            idsList += getFolderIDsByTitleRecursive(withList: item["Children"] as! [Dictionary<String,Any>], withTitle: title, withIDs: idsList)
            let testTitle = getItemTitle(withItem: item)
            if testTitle != nil {
                if testTitle == title {
                    idsList.append(item["WebBookmarkUUID"] as! String)
                }
            }
        }
    }
    return idsList
}

func getFolderIDByTitle(withPlist bookmarksPlist: Dictionary<String,Any>, withTitle title: String) throws -> String
{
    let folderIDs = getFolderIDsByTitleRecursive(withList: bookmarksPlist["Children"] as! [Dictionary<String,Any>], withTitle: title, withIDs: [String]())
    if folderIDs.count == 0 {
        throw "No folders found with title \"" + title + "\""
    }
    else if folderIDs.count == 1 {
        return folderIDs[0]
    }
    var folderAddresses = Dictionary<String,String>()
    var addressMap = Dictionary<String,String>()
    var i = 0
    print("Multiple folders found with title \"" + title + "\"")
    for id in folderIDs {
        let address = getReadableFolderAddress(withList: bookmarksPlist, withFolderID: id, withSeed: "")
        folderAddresses[address] = id
        addressMap[String(i)] = address
        print(String(i) + ": " + address)
        i += 1
    }
    var ans = ""
    var confirmed = false
    while !confirmed {
        print("Enter the number of the folder desired: ")
        ans = readLine()!
        if addressMap[ans] == nil || folderAddresses[addressMap[ans]!] == nil {
            print("Selection invalid, try again or quit with Ctrl+D")
            continue
        }
        else {
            confirmed = true
        }
    }

    return folderAddresses[addressMap[ans]!]!
}

func moveBookmark(withPlist bookmarksPlist: Dictionary<String,Any>,
                  withItem item: Dictionary<String,Any>,
                  toFolder destFolderTitle: String) throws -> Dictionary<String,Any>
{
    if destFolderTitle == "" {
        throw "Folder title cannot be an empty string"
    }
    else if item["WebBookmarkUUID"] == nil {
        throw "Item has no ID"
    }

    var mutPlist = bookmarksPlist
    let initialList = bookmarksPlist["Children"] as! [Dictionary<String,Any>]
    let itemID = item["WebBookmarkUUID"] as! String
    let destID = try getFolderIDByTitle(withPlist: bookmarksPlist, withTitle: destFolderTitle)
    mutPlist["Children"] = moveRecursive(withList: initialList, withItem: item, withItemID: itemID, withDestID: destID)
    return mutPlist
}

func moveBookmarksByPattern(withPlist bookmarksPlist: Dictionary<String,Any>,
                            withPattern pattern: String,
                            toFolder destFolderTitle: String) throws -> Dictionary<String,Any>
{
    let initialList = bookmarksPlist["Children"] as! [Dictionary<String,Any>]
    var itemsToMove = getBookmarkItems(withList: initialList, withAttr: "URLString", withPattern: pattern, withSeedList: [Dictionary<String,Any>]())
    let moreItemsToMove = getBookmarkItems(withList: initialList, withAttr: "title", withPattern: pattern, withSeedList: [Dictionary<String,Any>]())
    for item in moreItemsToMove {
        if !containsBookmarkItem(withList: itemsToMove, withItem: item) {
            itemsToMove.append(item)
        }
    }
    if itemsToMove.count < 1 {
        throw "Could not locate a bookmark with pattern \"" + pattern + "\""
    }
    var mutPlist = bookmarksPlist
    for item in itemsToMove {
        mutPlist = try moveBookmark(withPlist: bookmarksPlist, withItem: item, toFolder: destFolderTitle)
    }
    return mutPlist
}

func makeNewBookmark(bookmarkTitle title: String, bookmarkURL url: String) throws -> Dictionary<String,Any>
{
    if title == "" {
        throw "Bookmark title \"\" is invalid"
    }
    if url == "" {
        throw "Bookmark url \"\" is invalid"
    }
    var newBookmark = Dictionary<String,Any>()
    var uriDictionary = Dictionary<String,String>()
    uriDictionary["title"] = title
    newBookmark["URIDictionary"] = uriDictionary
    newBookmark["URLString"] = url
    newBookmark["WebBookmarkType"] = "WebBookmarkTypeLeaf"
    newBookmark["WebBookmarkUUID"] = UUID().uuidString
    return newBookmark
}

func addBookmarksAtFolderID(withList plist: Dictionary<String,Any>,
                            destFolderID destID: String,
                            withBookmarks bookmarks: [Dictionary<String,Any>]) -> Dictionary<String,Any>
{
    var mutPlist = plist
    var sublist = plist["Children"] as! [Dictionary<String,Any>]
    var i = 0
    while i < sublist.count {
        if sublist[i]["Children"] != nil {
            if itemIDInList(withList: sublist[i], withID: destID) {
                if sublist[i]["WebBookmarkUUID"] != nil && (sublist[i]["WebBookmarkUUID"] as! String) == destID {
                    let title = getItemTitle(withItem: sublist[i])
                    if title != nil {
                        print("Adding bookmarks to folder with title \"" + title! + "\"")
                    }
                    var destChildren = sublist[i]["Children"] as! [Dictionary<String,Any>]
                    destChildren += bookmarks
                    sublist[i]["Children"] = destChildren
                }
                else {
                    sublist[i] = addBookmarksAtFolderID(withList: sublist[i], destFolderID: destID, withBookmarks: bookmarks)
                }
            }
        }
        i += 1
    }
    mutPlist["Children"] = sublist
    return mutPlist
}

func addBookmark(withPlist bookmarksPlist: Dictionary<String,Any>,
                 toFolder destFolderTitle: String,
                 bookmarkTitle title: String,
                 bookmarkURL url: String) throws -> Dictionary<String,Any>
{
    let newBookmark = try makeNewBookmark(bookmarkTitle: title, bookmarkURL: url)
    var bookmarks = [Dictionary<String,Any>]()
    let destFolderID = try getFolderIDByTitle(withPlist: bookmarksPlist, withTitle: destFolderTitle)
    bookmarks.append(newBookmark)
    return addBookmarksAtFolderID(withList: bookmarksPlist, destFolderID: destFolderID, withBookmarks: bookmarks)
} 




/// Process Bookmark Management


let homeDirURL = FileManager.default.homeDirectoryForCurrentUser
let sourceListPath = homeDirURL.path + "/Library/Safari/Bookmarks.plist"
let workListPath = "Bookmarks.plist"

if let bookmarks = getPlist(withPath: sourceListPath) {
    var helpText = ""
    var dest = ""
    var pattern = ""
    var bookmarkTitle = ""
    var bookmarkURL = ""

    if CommandLine.argc < 2 {
        helpText = "swift ManageBookmarks.swift [add|move|remove]"
        errorQuit(errorText: "Missing required mode specification:\n" + helpText)
    }
    
    let arguments = CommandLine.arguments
    let mode = arguments[1]

    switch mode {
        case "add":
            helpText = "swift ManageBookmarks.swift add \"Bookmark Title\" \"Bookmark URL\" \"Destination folder title\""
            if CommandLine.argc < 3 || arguments[2] == "" {
                errorQuit(errorText: "Missing bookmark title\n" + helpText)
            }
            if CommandLine.argc < 4 || arguments[3] == "" {
                errorQuit(errorText: "Missing bookmark URL\n" + helpText)
            }
            if CommandLine.argc < 5 || arguments[4] == "" {
                errorQuit(errorText: "Missing destination folder title\n" + helpText)
            }
            bookmarkTitle = arguments[2]
            bookmarkURL = arguments[3]
            dest = arguments[4]
        case "move":
            let helpText = "swift ManageBookmarks.swift move [SearchPattern] \"Destination folder title\""
            if CommandLine.argc < 3 || arguments[2] == "" {
                errorQuit(errorText: "Missing regex title / URL pattern to find items to move\n" + helpText)
            }
            if CommandLine.argc < 4 || arguments[3] == "" {
                errorQuit(errorText: "Missing destination folder\n" + helpText)
            }
            pattern = arguments[2]
            dest = arguments[3]
        case "remove":
            let helpText = "swift ManageBookmarks.swift remove [SearchPattern]"
            if CommandLine.argc < 3 || arguments[2] == "" {
                errorQuit(errorText: "Missing regex title / URL pattern to find items to remove\n" + helpText)
            }
            pattern = arguments[2]
        default:
            throw "Unhandled mode specification, supported modes: [add|delete|move]"
    }

    if secureCopyItemAtPath(at: sourceListPath, to: workListPath) {
        print("Saved unmodified backup of original bookmarks file at " + workListPath)
    } else {
        print("Could not save backup copy at " + workListPath + " - aborting script, no changes made to original file")
        exit(1)
    }
    
    do {
        switch mode {
            case "add":
                let updatedBookmarks = try addBookmark(withPlist: bookmarks, toFolder: dest, bookmarkTitle: bookmarkTitle, bookmarkURL: bookmarkURL)
                let encodableBookmarks = NSDictionary(dictionary: updatedBookmarks)
                encodableBookmarks.write(toFile: sourceListPath, atomically: true)
            case "move":
                let updatedBookmarks = try moveBookmarksByPattern(withPlist: bookmarks, withPattern: pattern, toFolder: dest)
                let encodableBookmarks = NSDictionary(dictionary: updatedBookmarks)
                encodableBookmarks.write(toFile: sourceListPath, atomically: true)
            case "remove":
                let updatedBookmarks = try removeBookmarksByUrlOrTitle(withPlist: bookmarks, withPattern: pattern)
                print("Please confirm removal of all bookmarks matching pattern " + pattern + " in either title or URL")
                var ans = readLine()
                ans = ans!.lowercased()
                if (ans != "y" || ans != "yes") {
                    print("Change was not confirmed - Exiting with no change made")
                    exit(0)
                }
                let encodableBookmarks = NSDictionary(dictionary: updatedBookmarks)
                encodableBookmarks.write(toFile: sourceListPath, atomically: true)
            default:
                throw "False guard"
        }
    } catch (let error) {
        print(error.localizedDescription)
        exit(1)
    }
}


