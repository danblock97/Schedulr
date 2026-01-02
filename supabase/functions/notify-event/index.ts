// Supabase Edge Function to send APNs push notifications
// Supports multiple notification types: event invites, updates, cancellations, RSVP responses,
// reminders, group changes, subscription changes, and feature limit warnings
// Deploy with: supabase functions deploy notify-event

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const apnsUrl = Deno.env.get('APNS_URL') || 'https://api.sandbox.push.apple.com' // Use api.push.apple.com for production

// Notification types
type NotificationType = 
  | 'event_invite'
  | 'event_update'
  | 'event_cancellation'
  | 'rsvp_response'
  | 'event_reminder'
  | 'new_group_member'
  | 'group_member_left'
  | 'group_ownership_transfer'
  | 'group_renamed'
  | 'group_deleted'
  | 'subscription_change'
  | 'feature_limit_warning'

interface NotificationPayload {
  notification_type: NotificationType
  // Event-related
  event_id?: string
  creator_user_id?: string
  updater_user_id?: string
  responder_user_id?: string
  rsvp_status?: string
  // Group-related
  group_id?: string
  group_name?: string
  new_group_name?: string
  member_user_id?: string
  new_owner_user_id?: string
  actor_user_id?: string
  // Subscription-related
  target_user_id?: string
  change_type?: string
  new_tier?: string
  // Feature limit
  limit_type?: string
  current_count?: number
  max_count?: number
}

serve(async (req) => {
  try {
    const payload: NotificationPayload = await req.json()
    const notificationType = payload.notification_type || 'event_invite'

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Route to appropriate handler based on notification type
    switch (notificationType) {
      case 'event_invite':
        return await handleEventInvite(supabase, payload)
      case 'event_update':
        return await handleEventUpdate(supabase, payload)
      case 'event_cancellation':
        return await handleEventCancellation(supabase, payload)
      case 'rsvp_response':
        return await handleRSVPResponse(supabase, payload)
      case 'event_reminder':
        return await handleEventReminder(supabase, payload)
      case 'new_group_member':
        return await handleNewGroupMember(supabase, payload)
      case 'group_member_left':
        return await handleGroupMemberLeft(supabase, payload)
      case 'group_ownership_transfer':
        return await handleGroupOwnershipTransfer(supabase, payload)
      case 'group_renamed':
        return await handleGroupRenamed(supabase, payload)
      case 'group_deleted':
        return await handleGroupDeleted(supabase, payload)
      case 'subscription_change':
        return await handleSubscriptionChange(supabase, payload)
      case 'feature_limit_warning':
        return await handleFeatureLimitWarning(supabase, payload)
      default:
        return new Response(JSON.stringify({ error: `Unknown notification type: ${notificationType}` }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        })
    }
  } catch (error) {
    console.error('Error:', error)
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})

// ============================================
// Event Notification Handlers
// ============================================

async function handleEventInvite(supabase: any, payload: NotificationPayload) {
  const { event_id, creator_user_id } = payload
  
  if (!event_id) {
    return new Response(JSON.stringify({ error: 'event_id required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch event details
  const { data: event, error: eventError } = await supabase
    .from('calendar_events')
    .select('title, start_date, user_id, users(display_name)')
    .eq('id', event_id)
    .single()

  if (eventError || !event) {
    return new Response(JSON.stringify({ error: 'Event not found' }), { 
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch attendees - exclude creator if creator_user_id is provided
  let attendeesQuery = supabase
    .from('event_attendees')
    .select('user_id')
    .eq('event_id', event_id)
    .not('user_id', 'is', null)
  
  if (creator_user_id) {
    attendeesQuery = attendeesQuery.neq('user_id', creator_user_id)
  }
  
  const { data: attendees, error: attendeesError } = await attendeesQuery

  if (attendeesError) {
    console.error('Error fetching attendees:', attendeesError)
    return new Response(JSON.stringify({ error: 'Failed to fetch attendees' }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  if (!attendees || attendees.length === 0) {
    return new Response(JSON.stringify({ message: 'No attendees found' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = attendees.map((a: any) => a.user_id).filter(Boolean)
  const creatorName = event.users?.display_name || 'Someone'
  const eventTitle = event.title || 'New Event'
  const startDate = new Date(event.start_date)
  
  // Fetch user locales for proper date formatting
  const userLocales = await getUserLocales(supabase, userIds)
  
  // Format date per user with their locale
  const notifications: Array<{ userId: string, content: NotificationContent }> = []
  for (const userId of userIds) {
    const userLocale = userLocales.get(userId)
    const dateStr = formatDateForLocale(startDate, userLocale)
    
    notifications.push({
      userId,
      content: {
        title: `Invitation: ${eventTitle}`,
        body: `${creatorName} invited you to an event on ${dateStr}`,
        notification_type: 'event_invite',
        event_id: event_id
      }
    })
  }
  
  // Send notifications individually with per-user formatted dates
  return await sendNotificationsToUsersWithContent(supabase, notifications, 'notify_event_updates')
}

async function handleEventUpdate(supabase: any, payload: NotificationPayload) {
  const { event_id, updater_user_id } = payload
  
  if (!event_id) {
    return new Response(JSON.stringify({ error: 'event_id required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch event details
  const { data: event, error: eventError } = await supabase
    .from('calendar_events')
    .select('title, start_date, user_id, users(display_name)')
    .eq('id', event_id)
    .single()

  if (eventError || !event) {
    return new Response(JSON.stringify({ error: 'Event not found' }), { 
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch attendees - exclude the updater
  let attendeesQuery = supabase
    .from('event_attendees')
    .select('user_id')
    .eq('event_id', event_id)
    .not('user_id', 'is', null)
  
  if (updater_user_id) {
    attendeesQuery = attendeesQuery.neq('user_id', updater_user_id)
  }
  
  const { data: attendees } = await attendeesQuery

  if (!attendees || attendees.length === 0) {
    return new Response(JSON.stringify({ message: 'No attendees to notify' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = attendees.map((a: any) => a.user_id).filter(Boolean)
  const updaterName = event.users?.display_name || 'Someone'
  const eventTitle = event.title || 'Event'

  return await sendNotificationsToUsers(supabase, userIds, {
    title: `Event Updated: ${eventTitle}`,
    body: `${updaterName} updated the event details`,
    notification_type: 'event_update',
    event_id: event_id
  }, 'notify_event_updates')
}

async function handleEventCancellation(supabase: any, payload: NotificationPayload) {
  const { event_id, creator_user_id } = payload
  
  if (!event_id) {
    return new Response(JSON.stringify({ error: 'event_id required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch event details (might still exist or might be deleted - fetch what we can)
  const { data: event } = await supabase
    .from('calendar_events')
    .select('title, user_id, users(display_name)')
    .eq('id', event_id)
    .single()

  // Fetch attendees - exclude the creator/deleter
  let attendeesQuery = supabase
    .from('event_attendees')
    .select('user_id')
    .eq('event_id', event_id)
    .not('user_id', 'is', null)
  
  if (creator_user_id) {
    attendeesQuery = attendeesQuery.neq('user_id', creator_user_id)
  }
  
  const { data: attendees } = await attendeesQuery

  if (!attendees || attendees.length === 0) {
    return new Response(JSON.stringify({ message: 'No attendees to notify' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = attendees.map((a: any) => a.user_id).filter(Boolean)
  const creatorName = event?.users?.display_name || 'Someone'
  const eventTitle = event?.title || 'An event'

  return await sendNotificationsToUsers(supabase, userIds, {
    title: `Event Cancelled`,
    body: `${creatorName} cancelled "${eventTitle}"`,
    notification_type: 'event_cancellation',
    event_id: event_id
  }, 'notify_event_cancellations')
}

async function handleRSVPResponse(supabase: any, payload: NotificationPayload) {
  const { event_id, responder_user_id, rsvp_status } = payload
  
  if (!event_id || !responder_user_id || !rsvp_status) {
    return new Response(JSON.stringify({ error: 'event_id, responder_user_id, and rsvp_status required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch event details to get the creator
  const { data: event, error: eventError } = await supabase
    .from('calendar_events')
    .select('title, user_id')
    .eq('id', event_id)
    .single()

  if (eventError || !event) {
    return new Response(JSON.stringify({ error: 'Event not found' }), { 
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Don't notify if the responder is the event creator
  if (event.user_id === responder_user_id) {
    return new Response(JSON.stringify({ message: 'Responder is event creator, no notification needed' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch responder's name
  const { data: responder } = await supabase
    .from('users')
    .select('display_name')
    .eq('id', responder_user_id)
    .single()

  const responderName = responder?.display_name || 'Someone'
  const eventTitle = event.title || 'your event'
  
  let statusText = rsvp_status
  if (rsvp_status === 'going') statusText = 'is going to'
  else if (rsvp_status === 'maybe') statusText = 'might attend'
  else if (rsvp_status === 'declined') statusText = 'declined'

  return await sendNotificationsToUsers(supabase, [event.user_id], {
    title: `RSVP: ${eventTitle}`,
    body: `${responderName} ${statusText} "${eventTitle}"`,
    notification_type: 'rsvp_response',
    event_id: event_id
  }, 'notify_rsvp_responses')
}

async function handleEventReminder(supabase: any, payload: NotificationPayload) {
  const { event_id } = payload
  
  if (!event_id) {
    return new Response(JSON.stringify({ error: 'event_id required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch event details
  const { data: event, error: eventError } = await supabase
    .from('calendar_events')
    .select('title, start_date, location')
    .eq('id', event_id)
    .single()

  if (eventError || !event) {
    return new Response(JSON.stringify({ error: 'Event not found' }), { 
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch attendees who haven't received a reminder yet
  const { data: attendees } = await supabase
    .from('event_attendees')
    .select('user_id')
    .eq('event_id', event_id)
    .not('user_id', 'is', null)
    .is('reminder_sent_at', null)

  if (!attendees || attendees.length === 0) {
    return new Response(JSON.stringify({ message: 'No attendees to remind' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = attendees.map((a: any) => a.user_id).filter(Boolean)
  const eventTitle = event.title || 'Event'
  const startDate = new Date(event.start_date)
  
  // Fetch user locales for proper date formatting
  const userLocales = await getUserLocales(supabase, userIds)
  
  // Format date and time per user with their locale
  const notifications: Array<{ userId: string, content: NotificationContent }> = []
  for (const userId of userIds) {
    const userLocale = userLocales.get(userId)
    const dateStr = formatDateForLocale(startDate, userLocale)
    const timeStr = formatTimeForLocale(startDate, userLocale)
    
    notifications.push({
      userId,
      content: {
        title: `Reminder: ${eventTitle}`,
        body: `Starting ${dateStr} at ${timeStr}${event.location ? ` at ${event.location}` : ''}`,
        notification_type: 'event_reminder',
        event_id: event_id
      }
    })
  }
  
  // Send notifications individually with per-user formatted dates
  const result = await sendNotificationsToUsersWithContent(supabase, notifications, 'notify_event_reminders')

  // Mark reminders as sent
  await supabase
    .from('event_attendees')
    .update({ reminder_sent_at: new Date().toISOString() })
    .eq('event_id', event_id)
    .in('user_id', userIds)

  return result
}

// ============================================
// Group Notification Handlers
// ============================================

async function handleNewGroupMember(supabase: any, payload: NotificationPayload) {
  const { group_id, member_user_id } = payload
  
  if (!group_id || !member_user_id) {
    return new Response(JSON.stringify({ error: 'group_id and member_user_id required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch group details
  const { data: group } = await supabase
    .from('groups')
    .select('name')
    .eq('id', group_id)
    .single()

  // Fetch new member's name
  const { data: newMember } = await supabase
    .from('users')
    .select('display_name')
    .eq('id', member_user_id)
    .single()

  // Fetch all other group members
  const { data: members } = await supabase
    .from('group_members')
    .select('user_id')
    .eq('group_id', group_id)
    .neq('user_id', member_user_id)

  if (!members || members.length === 0) {
    return new Response(JSON.stringify({ message: 'No other members to notify' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = members.map((m: any) => m.user_id)
  const memberName = newMember?.display_name || 'Someone'
  const groupName = group?.name || 'a group'

  return await sendNotificationsToUsers(supabase, userIds, {
    title: `New Member`,
    body: `${memberName} joined ${groupName}`,
    notification_type: 'new_group_member',
    group_id: group_id
  }, 'notify_new_group_members')
}

async function handleGroupMemberLeft(supabase: any, payload: NotificationPayload) {
  const { group_id, member_user_id, actor_user_id } = payload
  
  if (!group_id || !member_user_id) {
    return new Response(JSON.stringify({ error: 'group_id and member_user_id required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch group details
  const { data: group } = await supabase
    .from('groups')
    .select('name')
    .eq('id', group_id)
    .single()

  // Fetch departed member's name
  const { data: departedMember } = await supabase
    .from('users')
    .select('display_name')
    .eq('id', member_user_id)
    .single()

  // Fetch remaining group members (exclude the one who left and optionally the actor)
  let membersQuery = supabase
    .from('group_members')
    .select('user_id')
    .eq('group_id', group_id)
    .neq('user_id', member_user_id)
  
  if (actor_user_id) {
    membersQuery = membersQuery.neq('user_id', actor_user_id)
  }

  const { data: members } = await membersQuery

  if (!members || members.length === 0) {
    return new Response(JSON.stringify({ message: 'No other members to notify' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = members.map((m: any) => m.user_id)
  const memberName = departedMember?.display_name || 'Someone'
  const groupName = group?.name || 'the group'

  return await sendNotificationsToUsers(supabase, userIds, {
    title: `Member Left`,
    body: `${memberName} left ${groupName}`,
    notification_type: 'group_member_left',
    group_id: group_id
  }, 'notify_group_member_left')
}

async function handleGroupOwnershipTransfer(supabase: any, payload: NotificationPayload) {
  const { group_id, new_owner_user_id, actor_user_id } = payload
  
  if (!group_id || !new_owner_user_id) {
    return new Response(JSON.stringify({ error: 'group_id and new_owner_user_id required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch group details
  const { data: group } = await supabase
    .from('groups')
    .select('name')
    .eq('id', group_id)
    .single()

  const groupName = group?.name || 'a group'

  // Notify the new owner
  return await sendNotificationsToUsers(supabase, [new_owner_user_id], {
    title: `Ownership Transfer`,
    body: `You are now the owner of ${groupName}`,
    notification_type: 'group_ownership_transfer',
    group_id: group_id
  }, 'notify_group_ownership_transfer')
}

async function handleGroupRenamed(supabase: any, payload: NotificationPayload) {
  const { group_id, new_group_name, actor_user_id } = payload
  
  if (!group_id || !new_group_name) {
    return new Response(JSON.stringify({ error: 'group_id and new_group_name required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch actor's name
  let actorName = 'Someone'
  if (actor_user_id) {
    const { data: actor } = await supabase
      .from('users')
      .select('display_name')
      .eq('id', actor_user_id)
      .single()
    actorName = actor?.display_name || 'Someone'
  }

  // Fetch all group members except the actor
  let membersQuery = supabase
    .from('group_members')
    .select('user_id')
    .eq('group_id', group_id)
  
  if (actor_user_id) {
    membersQuery = membersQuery.neq('user_id', actor_user_id)
  }

  const { data: members } = await membersQuery

  if (!members || members.length === 0) {
    return new Response(JSON.stringify({ message: 'No other members to notify' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = members.map((m: any) => m.user_id)

  return await sendNotificationsToUsers(supabase, userIds, {
    title: `Group Renamed`,
    body: `${actorName} renamed the group to "${new_group_name}"`,
    notification_type: 'group_renamed',
    group_id: group_id
  }, 'notify_group_renamed')
}

async function handleGroupDeleted(supabase: any, payload: NotificationPayload & { user_ids?: string[], title?: string, body?: string, preference_key?: string }) {
  const { group_name, actor_user_id, user_ids, title, body, preference_key } = payload
  
  // The group is deleted before this is called, so we need user_ids passed directly
  if (!user_ids || user_ids.length === 0) {
    return new Response(JSON.stringify({ error: 'user_ids required (group members must be fetched before deletion)' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Filter out the actor (the one who deleted the group)
  let usersToNotify = user_ids
  if (actor_user_id) {
    usersToNotify = user_ids.filter(id => id !== actor_user_id)
  }

  if (usersToNotify.length === 0) {
    return new Response(JSON.stringify({ message: 'No users to notify after filtering' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Use provided title/body or defaults
  const notificationTitle = title || 'Group Deleted'
  const notificationBody = body || (group_name ? `"${group_name}" has been deleted` : 'A group you were in has been deleted')

  return await sendNotificationsToUsers(supabase, usersToNotify, {
    title: notificationTitle,
    body: notificationBody,
    notification_type: 'group_deleted'
  }, preference_key || 'notify_group_deleted')
}

// ============================================
// Subscription Notification Handlers
// ============================================

async function handleSubscriptionChange(supabase: any, payload: NotificationPayload) {
  const { target_user_id, change_type, new_tier } = payload
  
  if (!target_user_id || !change_type) {
    return new Response(JSON.stringify({ error: 'target_user_id and change_type required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  let title = 'Subscription Update'
  let body = ''

  switch (change_type) {
    case 'upgraded':
      title = 'Welcome to Pro!'
      body = 'Your subscription has been upgraded. Enjoy unlimited features!'
      break
    case 'downgraded':
      title = 'Subscription Changed'
      body = 'Your subscription has been changed to Free tier.'
      break
    case 'expired':
      title = 'Subscription Expired'
      body = 'Your Pro subscription has expired. Renew to continue enjoying premium features.'
      break
    case 'grace_period_started':
      title = 'Grace Period Started'
      body = 'Your subscription has entered a grace period. Please update your payment method.'
      break
    case 'grace_period_ending':
      title = 'Grace Period Ending Soon'
      body = 'Your grace period is ending soon. Update your payment to avoid losing access.'
      break
    default:
      body = `Your subscription status has changed to ${change_type}`
  }

  return await sendNotificationsToUsers(supabase, [target_user_id], {
    title,
    body,
    notification_type: 'subscription_change'
  }, 'notify_subscription_changes')
}

async function handleFeatureLimitWarning(supabase: any, payload: NotificationPayload) {
  const { target_user_id, limit_type, current_count, max_count } = payload
  
  if (!target_user_id || !limit_type) {
    return new Response(JSON.stringify({ error: 'target_user_id and limit_type required' }), { 
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  let title = 'Approaching Limit'
  let body = ''

  switch (limit_type) {
    case 'groups':
      body = `You've used ${current_count} of ${max_count} groups. Upgrade to Pro for unlimited groups.`
      break
    case 'group_members':
      body = `Your group has ${current_count} of ${max_count} members. Upgrade to Pro for unlimited members.`
      break
    case 'ai_requests':
      body = `You've used ${current_count} of ${max_count} AI requests this month. Upgrade to Pro for more.`
      break
    default:
      body = `You're approaching your ${limit_type} limit (${current_count}/${max_count}).`
  }

  return await sendNotificationsToUsers(supabase, [target_user_id], {
    title,
    body,
    notification_type: 'feature_limit_warning'
  }, 'notify_feature_limit_warnings')
}

// ============================================
// Helper Functions
// ============================================

interface NotificationContent {
  title: string
  body: string
  notification_type: NotificationType
  event_id?: string
  group_id?: string
}

/**
 * Fetches user locales from user_settings
 * Returns a map of user_id -> locale identifier
 */
async function getUserLocales(supabase: any, userIds: string[]): Promise<Map<string, string>> {
  const localeMap = new Map<string, string>()
  
  if (!userIds || userIds.length === 0) {
    return localeMap
  }
  
  const { data: settings } = await supabase
    .from('user_settings')
    .select('user_id, locale')
    .in('user_id', userIds)
  
  if (settings && settings.length > 0) {
    for (const setting of settings) {
      if (setting.locale) {
        localeMap.set(setting.user_id, setting.locale)
      }
    }
  }
  
  return localeMap
}

/**
 * Formats a date using the user's locale, or falls back to en_US
 */
function formatDateForLocale(date: Date, locale?: string): string {
  try {
    // Convert locale identifier (e.g., "en_GB") to format expected by toLocaleDateString
    // toLocaleDateString expects format like "en-GB" (hyphen, not underscore)
    const normalizedLocale = locale ? locale.replace('_', '-') : 'en-US'
    return date.toLocaleDateString(normalizedLocale)
  } catch (error) {
    // Fallback to en-US if locale is invalid
    return date.toLocaleDateString('en-US')
  }
}

/**
 * Formats a time using the user's locale, or falls back to en_US
 */
function formatTimeForLocale(date: Date, locale?: string): string {
  try {
    const normalizedLocale = locale ? locale.replace('_', '-') : 'en-US'
    return date.toLocaleTimeString(normalizedLocale, { hour: '2-digit', minute: '2-digit' })
  } catch (error) {
    return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
  }
}

/**
 * Sends notifications with per-user content (for date formatting per locale)
 */
async function sendNotificationsToUsersWithContent(
  supabase: any,
  notifications: Array<{ userId: string, content: NotificationContent }>,
  preferenceKey?: string
): Promise<Response> {
  if (!notifications || notifications.length === 0) {
    return new Response(JSON.stringify({ message: 'No notifications to send' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const userIds = notifications.map(n => n.userId)
  
  // Filter users based on their notification preferences
  let filteredNotifications = notifications
  if (preferenceKey) {
    const { data: settings } = await supabase
      .from('user_settings')
      .select(`user_id, ${preferenceKey}`)
      .in('user_id', userIds)

    if (settings && settings.length > 0) {
      const usersWithPreferenceOff = settings
        .filter((s: any) => s[preferenceKey] === false)
        .map((s: any) => s.user_id)
      
      filteredNotifications = notifications.filter(n => !usersWithPreferenceOff.includes(n.userId))
    }
  }

  if (filteredNotifications.length === 0) {
    return new Response(JSON.stringify({ message: 'All users have this notification disabled' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch device tokens for filtered users
  const filteredUserIds = filteredNotifications.map(n => n.userId)
  const { data: devices, error: devicesError } = await supabase
    .from('user_devices')
    .select('user_id, apns_token')
    .in('user_id', filteredUserIds)

  if (devicesError) {
    console.error('Error fetching device tokens:', devicesError)
    return new Response(JSON.stringify({ error: 'Failed to fetch device tokens' }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  if (!devices || devices.length === 0) {
    return new Response(JSON.stringify({ message: 'No device tokens found', tokens: 0 }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Create a map of userId -> content for quick lookup
  const contentByUser = new Map<string, NotificationContent>()
  for (const notif of filteredNotifications) {
    contentByUser.set(notif.userId, notif.content)
  }

  // Group devices by user
  const devicesByUser = new Map<string, any[]>()
  for (const device of devices) {
    if (!device.apns_token) continue
    const userId = device.user_id
    if (!devicesByUser.has(userId)) {
      devicesByUser.set(userId, [])
    }
    devicesByUser.get(userId)!.push(device)
  }

  const results: any[] = []

  // Send notifications with per-user content
  for (const [userId, userDevices] of devicesByUser) {
    const content = contentByUser.get(userId)
    if (!content) continue // Skip if no content for this user
    
    for (const device of userDevices) {
      const notification: any = {
        aps: {
          alert: {
            title: content.title,
            body: content.body,
          },
          sound: 'default',
          'content-available': 1,
          badge: 1,
        },
        notification_type: content.notification_type,
      }

      // Add optional fields
      if (content.event_id) notification.event_id = content.event_id
      if (content.group_id) notification.group_id = content.group_id

      try {
        const jwtToken = await getApnsToken()

        const response = await fetch(`${apnsUrl}/3/device/${device.apns_token}`, {
          method: 'POST',
          headers: {
            'apns-topic': Deno.env.get('APNS_BUNDLE_ID') || 'uk.co.schedulr.Schedulr',
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'authorization': `bearer ${jwtToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(notification),
        })

        results.push({ token: device.apns_token.substring(0, 8) + '...', status: response.status })
      } catch (err: any) {
        results.push({ token: device.apns_token.substring(0, 8) + '...', error: err.message })
      }
    }
  }

  return new Response(JSON.stringify({ 
    message: `Sent ${results.length} notifications`,
    results 
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  })
}

async function sendNotificationsToUsers(
  supabase: any, 
  userIds: string[], 
  content: NotificationContent,
  preferenceKey?: string
): Promise<Response> {
  if (!userIds || userIds.length === 0) {
    return new Response(JSON.stringify({ message: 'No users to notify' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Filter users based on their notification preferences
  let filteredUserIds = userIds
  if (preferenceKey) {
    const { data: settings } = await supabase
      .from('user_settings')
      .select(`user_id, ${preferenceKey}`)
      .in('user_id', userIds)

    if (settings && settings.length > 0) {
      // Get users who have the preference enabled (or don't have settings = use default true)
      const usersWithPreferenceOff = settings
        .filter((s: any) => s[preferenceKey] === false)
        .map((s: any) => s.user_id)
      
      filteredUserIds = userIds.filter(id => !usersWithPreferenceOff.includes(id))
    }
  }

  if (filteredUserIds.length === 0) {
    return new Response(JSON.stringify({ message: 'All users have this notification disabled' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Fetch device tokens for filtered users
  const { data: devices, error: devicesError } = await supabase
    .from('user_devices')
    .select('user_id, apns_token')
    .in('user_id', filteredUserIds)

  if (devicesError) {
    console.error('Error fetching device tokens:', devicesError)
    return new Response(JSON.stringify({ error: 'Failed to fetch device tokens' }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  if (!devices || devices.length === 0) {
    return new Response(JSON.stringify({ message: 'No device tokens found', tokens: 0 }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Group devices by user
  const devicesByUser = new Map<string, any[]>()
  for (const device of devices) {
    if (!device.apns_token) continue
    const userId = device.user_id
    if (!devicesByUser.has(userId)) {
      devicesByUser.set(userId, [])
    }
    devicesByUser.get(userId)!.push(device)
  }

  const results: any[] = []

  // Send notifications
  for (const [userId, userDevices] of devicesByUser) {
    for (const device of userDevices) {
      const notification: any = {
        aps: {
          alert: {
            title: content.title,
            body: content.body,
          },
          sound: 'default',
          'content-available': 1,
          badge: 1,
        },
        notification_type: content.notification_type,
      }

      // Add optional fields
      if (content.event_id) notification.event_id = content.event_id
      if (content.group_id) notification.group_id = content.group_id

      try {
        const jwtToken = await getApnsToken()

        const response = await fetch(`${apnsUrl}/3/device/${device.apns_token}`, {
          method: 'POST',
          headers: {
            'apns-topic': Deno.env.get('APNS_BUNDLE_ID') || 'uk.co.schedulr.Schedulr',
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'authorization': `bearer ${jwtToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(notification),
        })

        results.push({ token: device.apns_token.substring(0, 8) + '...', status: response.status })
      } catch (err: any) {
        results.push({ token: device.apns_token.substring(0, 8) + '...', error: err.message })
      }
    }
  }

  return new Response(JSON.stringify({ 
    message: `Sent ${results.length} notifications`,
    results 
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  })
}

// Generate APNs JWT token using your .p8 key
async function getApnsToken(): Promise<string> {
  const apnsKeyId = Deno.env.get('APNS_KEY_ID')
  const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
  const apnsKey = Deno.env.get('APNS_PRIVATE_KEY')

  if (!apnsKeyId || !apnsTeamId || !apnsKey) {
    throw new Error('Missing APNs credentials. Set APNS_KEY_ID, APNS_TEAM_ID, and APNS_PRIVATE_KEY environment variables.')
  }

  // Create JWT header
  const header = {
    alg: 'ES256',
    kid: apnsKeyId
  }

  // Create JWT payload
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: apnsTeamId,
    iat: now,
    exp: now + (60 * 60) // 1 hour expiration
  }

  // Base64URL encode header and payload
  const encodeBase64URL = (obj: any) => {
    const json = JSON.stringify(obj)
    const base64 = btoa(json)
    return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
  }

  const headerEncoded = encodeBase64URL(header)
  const payloadEncoded = encodeBase64URL(payload)
  const message = `${headerEncoded}.${payloadEncoded}`

  // Import the private key
  const privateKeyPem = apnsKey.replace(/\\n/g, '\n')
  const privateKeyDer = pemToDer(privateKeyPem)

  // Import key for signing
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    privateKeyDer,
    {
      name: 'ECDSA',
      namedCurve: 'P-256'
    },
    false,
    ['sign']
  )

  // Sign the message
  const messageBytes = new TextEncoder().encode(message)
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    cryptoKey,
    messageBytes
  )

  // Base64URL encode signature
  const signatureEncoded = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')

  return `${message}.${signatureEncoded}`
}

// Helper function to convert PEM to DER
function pemToDer(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')

  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes
}
