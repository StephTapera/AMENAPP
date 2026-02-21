#!/bin/bash
# Script to add notification type parameter to all sendPushNotificationToUser calls

FILE="pushNotifications.js"

# Reply notifications (line ~389)
sed -i '' 's/sendPushNotificationToUser(\(.*\)type: "reply",\(.*\)),$/sendPushNotificationToUser(\1type: "reply",\2), "reply",/' "$FILE"

# Mention notifications (line ~475)  
sed -i '' 's/\(await sendPushNotificationToUser(.*type: "mention",.*)\),$/\1, "mention",/' "$FILE"

# Amen notifications (line ~607)
sed -i '' 's/\(await sendPushNotificationToUser(.*type: "amen",.*)\),$/\1, "amen",/' "$FILE"

# Repost notifications (line ~744)
sed -i '' 's/\(await sendPushNotificationToUser(.*type: "repost",.*)\),$/\1, "repost",/' "$FILE"

echo "✅ Notification type parameters added"
