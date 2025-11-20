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
        const jwtToken = await getApnsToken()

        const response = await fetch(`${apnsUrl}/3/device/${token}`, {
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
