// Backend Genkit Flows for Notifications
// File: functions/src/notificationFlows.ts
// 
// This is TypeScript/JavaScript code that runs on Firebase Cloud Functions
// Copy this to your Firebase project

import { genkit, z } from 'genkit';
import { firebase } from '@genkit-ai/firebase';
import { googleAI, gemini15Flash, gemini15Pro } from '@genkit-ai/google-ai';

// Initialize Genkit with Firebase and Google AI
const ai = genkit({
  plugins: [
    firebase(),
    googleAI({ apiKey: process.env.GOOGLE_API_KEY }),
  ],
});

// ============================================================================
// FLOW 1: Generate Personalized Notification Text
// ============================================================================

export const generateNotificationText = ai.defineFlow(
  {
    name: 'generateNotificationText',
    inputSchema: z.object({
      eventType: z.enum(['message', 'match', 'prayer_request', 'prayer_answer', 
                         'event_reminder', 'like', 'comment', 'group_invite']),
      senderName: z.string(),
      context: z.string(),
      recipientInterests: z.array(z.string()).default([]),
      sharedInterests: z.array(z.string()).default([]),
      metadata: z.record(z.any()).default({}),
    }),
    outputSchema: z.object({
      title: z.string(),
      body: z.string(),
      priority: z.enum(['high', 'medium', 'low']),
      category: z.string(),
    }),
  },
  async (input) => {
    // Build context-aware prompt
    const sharedInterestsText = input.sharedInterests.length > 0
      ? `You both share these interests: ${input.sharedInterests.join(', ')}`
      : '';
    
    const recipientInterestsText = input.recipientInterests.length > 0
      ? `Recipient's interests: ${input.recipientInterests.join(', ')}`
      : '';

    const prompt = `You are a notification writer for a Christian dating and community app called AMEN.

Event Type: ${input.eventType}
From: ${input.senderName}
Context: ${input.context}
${sharedInterestsText}
${recipientInterestsText}

Generate a warm, encouraging, and faith-centered notification.

Requirements:
- Title: Max 40 characters, engaging and clear
- Body: Max 120 characters, include relevant context
- Be personal and mention shared interests when available
- Use appropriate Christian language but stay modern and relatable
- Convey urgency for high-priority items (prayer requests)
- Be encouraging and positive

Return JSON with: title, body, priority (high/medium/low), category`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.7,
        maxOutputTokens: 200,
      },
    });

    // Parse AI response
    const text = response.text();
    
    // Try to parse JSON from response
    try {
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        const parsed = JSON.parse(jsonMatch[0]);
        return {
          title: parsed.title || `${input.senderName} on AMEN`,
          body: parsed.body || input.context.substring(0, 100),
          priority: parsed.priority || determinePriority(input.eventType),
          category: parsed.category || input.eventType,
        };
      }
    } catch (e) {
      console.warn('Failed to parse AI response as JSON, using fallback');
    }

    // Fallback if parsing fails
    return generateFallbackNotification(input);
  }
);

// ============================================================================
// FLOW 2: Summarize Multiple Notifications
// ============================================================================

export const summarizeNotifications = ai.defineFlow(
  {
    name: 'summarizeNotifications',
    inputSchema: z.object({
      notifications: z.array(z.object({
        type: z.string(),
        sender: z.string(),
        message: z.string(),
        timestamp: z.number().optional(),
      })),
      maxLength: z.number().default(100),
    }),
    outputSchema: z.object({
      summary: z.string(),
      count: z.number(),
      topPriority: z.string(),
    }),
  },
  async (input) => {
    const notificationList = input.notifications
      .map((n, i) => `${i + 1}. ${n.sender}: ${n.message} (${n.type})`)
      .join('\n');

    const prompt = `You are summarizing multiple notifications for a Christian community app.

Notifications (${input.notifications.length} total):
${notificationList}

Create ONE engaging summary that:
- Is under ${input.maxLength} characters
- Mentions the most important people/events
- Groups similar notifications together
- Sounds warm and encouraging
- Makes the user want to open the app

Examples:
"Sarah, John, and 3 others engaged with you today! 💬"
"Your prayer circle prayed for 5 requests - 2 answered! 🙏"
"3 believers near you want to connect ✨"

Return JSON with: summary, count (total notifications), topPriority (most important notification type)`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.8,
        maxOutputTokens: 150,
      },
    });

    const text = response.text();
    
    try {
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        const parsed = JSON.parse(jsonMatch[0]);
        return {
          summary: parsed.summary,
          count: input.notifications.length,
          topPriority: parsed.topPriority || input.notifications[0].type,
        };
      }
    } catch (e) {
      console.warn('Failed to parse summary, using fallback');
    }

    // Fallback
    return {
      summary: `${input.notifications.length} updates from your AMEN community await! ✨`,
      count: input.notifications.length,
      topPriority: input.notifications[0].type,
    };
  }
);

// ============================================================================
// FLOW 3: Optimize Notification Timing
// ============================================================================

export const optimizeNotificationTiming = ai.defineFlow(
  {
    name: 'optimizeNotificationTiming',
    inputSchema: z.object({
      userId: z.string(),
      notificationType: z.string(),
      priority: z.enum(['high', 'medium', 'low']),
      userTimezone: z.string(),
      activityPatterns: z.array(z.object({
        hour: z.number(),
        activeCount: z.number(),
      })),
      currentHour: z.number(),
    }),
    outputSchema: z.object({
      sendImmediately: z.boolean(),
      delayMinutes: z.number(),
      reasoning: z.string(),
    }),
  },
  async (input) => {
    // High priority always sends immediately
    if (input.priority === 'high') {
      return {
        sendImmediately: true,
        delayMinutes: 0,
        reasoning: 'High priority notification - urgent delivery required',
      };
    }

    // Find user's most active hours
    const sortedPatterns = input.activityPatterns
      .sort((a, b) => b.activeCount - a.activeCount);
    
    const mostActiveHour = sortedPatterns[0]?.hour || 9; // Default to 9am
    const currentHour = input.currentHour;

    // Don't send between 11pm and 7am
    if (currentHour >= 23 || currentHour < 7) {
      const delayUntilMorning = currentHour >= 23 
        ? (7 - currentHour + 24) * 60 
        : (7 - currentHour) * 60;
      
      return {
        sendImmediately: false,
        delayMinutes: delayUntilMorning,
        reasoning: 'Delaying until morning to respect user\'s rest time',
      };
    }

    // If current time is within 2 hours of peak activity, send now
    if (Math.abs(currentHour - mostActiveHour) <= 2) {
      return {
        sendImmediately: true,
        delayMinutes: 0,
        reasoning: 'Sending now - user is typically active around this time',
      };
    }

    // Medium priority: delay until next active period
    if (input.priority === 'medium') {
      let delayMinutes = 0;
      
      if (currentHour < mostActiveHour) {
        delayMinutes = (mostActiveHour - currentHour) * 60;
      } else {
        // Wait until next day's peak time
        delayMinutes = (24 - currentHour + mostActiveHour) * 60;
      }

      return {
        sendImmediately: false,
        delayMinutes: Math.min(delayMinutes, 720), // Max 12 hours delay
        reasoning: `Scheduling for user's peak activity time (${mostActiveHour}:00)`,
      };
    }

    // Low priority: batch for daily digest
    return {
      sendImmediately: false,
      delayMinutes: 1440, // 24 hours
      reasoning: 'Low priority - will be included in next daily digest',
    };
  }
);

// ============================================================================
// Helper Functions
// ============================================================================

function determinePriority(eventType: string): 'high' | 'medium' | 'low' {
  const highPriority = ['prayer_request', 'event_reminder'];
  const lowPriority = ['like', 'profile_view', 'verse_of_day'];
  
  if (highPriority.includes(eventType)) return 'high';
  if (lowPriority.includes(eventType)) return 'low';
  return 'medium';
}

function generateFallbackNotification(input: any) {
  const templates = {
    message: {
      title: `${input.senderName} sent you a message`,
      body: input.context.substring(0, 100),
    },
    match: {
      title: `New match: ${input.senderName}!`,
      body: input.sharedInterests.length > 0
        ? `You both love ${input.sharedInterests[0]}! ❤️`
        : `${input.senderName} wants to connect with you!`,
    },
    prayer_request: {
      title: `🙏 ${input.senderName} needs prayer`,
      body: input.context.substring(0, 100),
    },
    like: {
      title: `${input.senderName} liked your post`,
      body: 'See what they thought about your content',
    },
    event_reminder: {
      title: `Event reminder: ${input.context}`,
      body: 'Your event is starting soon!',
    },
  };

  const template = templates[input.eventType as keyof typeof templates] || {
    title: `${input.senderName} on AMEN`,
    body: input.context,
  };

  return {
    title: template.title,
    body: template.body,
    priority: determinePriority(input.eventType),
    category: input.eventType,
  };
}

// ============================================================================
// Cloud Function to Process Notification Queue
// ============================================================================

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// This function watches the notificationQueue collection
// and sends FCM notifications
export const processNotificationQueue = functions.firestore
  .document('notificationQueue/{notificationId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    
    const message = {
      token: notification.token,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      console.log('✅ Notification sent successfully:', response);
      
      // Delete from queue after sending
      await snap.ref.delete();
    } catch (error) {
      console.error('❌ Error sending notification:', error);
      
      // Update with error status
      await snap.ref.update({
        status: 'failed',
        error: error.message,
      });
    }
  });

// ============================================================================
// Scheduled Function to Process Scheduled Notifications
// ============================================================================

export const processScheduledNotifications = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    
    const snapshot = await admin.firestore()
      .collection('scheduledNotifications')
      .where('status', '==', 'scheduled')
      .where('scheduledFor', '<=', now)
      .limit(100)
      .get();

    console.log(`Processing ${snapshot.size} scheduled notifications`);

    const promises = snapshot.docs.map(async (doc) => {
      const notification = doc.data();
      
      // Move to notificationQueue for sending
      await admin.firestore()
        .collection('notificationQueue')
        .add({
          token: notification.token,
          title: notification.title,
          body: notification.body,
          data: notification.data,
          priority: 'high',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      // Update status
      await doc.ref.update({ status: 'sent' });
    });

    await Promise.all(promises);
    
    console.log(`✅ Processed ${promises.length} scheduled notifications`);
    return null;
  });
