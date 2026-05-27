import Foundation

enum AmenHandoff {

    enum BereanChat {
        static let activityType = "app.amen.berean.chat"

        enum Keys {
            static let sessionId = "sessionId"
            static let lastQuery = "lastQuery"
        }

        static func makeActivity(sessionId: String, lastQuery: String?) -> NSUserActivity {
            let activity = NSUserActivity(activityType: activityType)
            activity.title = "Berean AI Session"
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.requiredUserInfoKeys = [Keys.sessionId]
            activity.addUserInfoEntries(from: [
                Keys.sessionId: sessionId,
                Keys.lastQuery: lastQuery ?? NSNull() as Any
            ])
            return activity
        }

        static func reference(from activity: NSUserActivity) -> (sessionId: String, lastQuery: String?)? {
            guard activity.activityType == activityType,
                  let info = activity.userInfo,
                  let sessionId = info[Keys.sessionId] as? String
            else { return nil }
            let lastQuery = info[Keys.lastQuery] as? String
            return (sessionId: sessionId, lastQuery: lastQuery)
        }
    }

    enum PrayerThread {
        static let activityType = "app.amen.prayer.thread"

        enum Keys {
            static let threadId = "threadId"
            static let threadTitle = "threadTitle"
        }

        static func makeActivity(threadId: String, threadTitle: String) -> NSUserActivity {
            let activity = NSUserActivity(activityType: activityType)
            activity.title = "Prayer Thread: \(threadTitle)"
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.requiredUserInfoKeys = [Keys.threadId, Keys.threadTitle]
            activity.addUserInfoEntries(from: [
                Keys.threadId: threadId,
                Keys.threadTitle: threadTitle
            ])
            return activity
        }

        static func reference(from activity: NSUserActivity) -> (threadId: String, threadTitle: String)? {
            guard activity.activityType == activityType,
                  let info = activity.userInfo,
                  let threadId = info[Keys.threadId] as? String,
                  let threadTitle = info[Keys.threadTitle] as? String
            else { return nil }
            return (threadId: threadId, threadTitle: threadTitle)
        }
    }

    enum ChurchProfile {
        static let activityType = "app.amen.church.profile"

        enum Keys {
            static let churchId = "churchId"
            static let churchName = "churchName"
        }

        static func makeActivity(churchId: String, churchName: String) -> NSUserActivity {
            let activity = NSUserActivity(activityType: activityType)
            activity.title = "Church: \(churchName)"
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.requiredUserInfoKeys = [Keys.churchId, Keys.churchName]
            activity.addUserInfoEntries(from: [
                Keys.churchId: churchId,
                Keys.churchName: churchName
            ])
            return activity
        }

        static func reference(from activity: NSUserActivity) -> (churchId: String, churchName: String)? {
            guard activity.activityType == activityType,
                  let info = activity.userInfo,
                  let churchId = info[Keys.churchId] as? String,
                  let churchName = info[Keys.churchName] as? String
            else { return nil }
            return (churchId: churchId, churchName: churchName)
        }
    }

    enum PrayerRoom {
        static let activityType = "app.amen.prayer.room"

        enum Keys {
            static let roomId = "roomId"
            static let roomName = "roomName"
        }

        static func makeActivity(roomId: String, roomName: String) -> NSUserActivity {
            let activity = NSUserActivity(activityType: activityType)
            activity.title = "Prayer Room: \(roomName)"
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.requiredUserInfoKeys = [Keys.roomId, Keys.roomName]
            activity.addUserInfoEntries(from: [
                Keys.roomId: roomId,
                Keys.roomName: roomName
            ])
            return activity
        }

        static func reference(from activity: NSUserActivity) -> (roomId: String, roomName: String)? {
            guard activity.activityType == activityType,
                  let info = activity.userInfo,
                  let roomId = info[Keys.roomId] as? String,
                  let roomName = info[Keys.roomName] as? String
            else { return nil }
            return (roomId: roomId, roomName: roomName)
        }
    }
}
