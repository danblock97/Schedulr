// Supabase Edge Function to send APNs push notifications for event invites
// Deploy with: supabase functions deploy notify-event

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const apnsUrl = Deno.env.get('APNS_URL') || 'https://api.sandbox.push.apple.com' // Use api.push.apple.com for production

serve(async (req) => {
  try {
    const { event_id } = await req.json()
    
    if (!event_id) {
      return new Response(JSON.stringify({ error: 'event_id required' }), { 
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

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

    // Fetch attendees
    const { data: attendees, error: attendeesError } = await supabase
      .from('event_attendees')
      .select('user_id')
      .eq('event_id', event_id)
      .not('user_id', 'is', null)

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

    // Extract user IDs and fetch their device tokens
    const userIds = attendees.map((a: any) => a.user_id).filter(Boolean)
    
    const { data: devices, error: devicesError } = await supabase
      .from('user_devices')
      .select('apns_token')
      .in('user_id', userIds)

    if (devicesError) {
      console.error('Error fetching device tokens:', devicesError)
      return new Response(JSON.stringify({ error: 'Failed to fetch device tokens' }), { 
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    // Extract tokens
    const tokens: string[] = devices?.map((d: any) => d.apns_token).filter(Boolean) || []

    if (tokens.length === 0) {
      return new Response(JSON.stringify({ message: 'No device tokens found', tokens: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    // Send APNs notifications
    const creatorName = event.users?.display_name || 'Someone'
    const eventTitle = event.title || 'New Event'
    const startDate = new Date(event.start_date)
    const dateStr = startDate.toLocaleDateString()

    const notification = {
      aps: {
        alert: {
          title: `Invitation: ${eventTitle}`,
          body: `${creatorName} invited you to an event on ${dateStr}`,
        },
        sound: 'default',
        badge: 1,
      },
      event_id: event_id,
    }

    const results = []
    for (const token of tokens) {
      try {
        const response = await fetch(`${apnsUrl}/3/device/${token}`, {
          method: 'POST',
          headers: {
            'apns-topic': Deno.env.get('APNS_BUNDLE_ID') || 'uk.co.schedulr.Schedulr',
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'authorization': `bearer ${await getApnsToken()}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(notification),
        })

        results.push({ token: token.substring(0, 8) + '...', status: response.status })
      } catch (err) {
        results.push({ token: token.substring(0, 8) + '...', error: err.message })
      }
    }

    return new Response(JSON.stringify({ 
      message: `Sent ${results.length} notifications`,
      results 
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Error:', error)
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})

// Generate APNs JWT token (you'll need to implement this with your .p8 key)
async function getApnsToken(): Promise<string> {
  // TODO: Implement JWT signing with your APNs .p8 key
  // See: https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_token-based_connection_to_apns
  // You'll need: APNS_KEY_ID, APNS_TEAM_ID, and the .p8 key file
  
  throw new Error('APNs token generation not implemented - see README')
}
