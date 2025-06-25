import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

console.log('🔧 Supabase Configuration Check:', {
  url: supabaseUrl ? 'Present' : 'Missing',
  urlValid: supabaseUrl?.startsWith('https://') && supabaseUrl?.includes('.supabase.co'),
  key: supabaseAnonKey ? 'Present' : 'Missing',
  keyValid: supabaseAnonKey?.length > 50 && supabaseAnonKey?.startsWith('eyJ'),
  environment: import.meta.env.MODE,
  urlLength: supabaseUrl?.length || 0,
  keyLength: supabaseAnonKey?.length || 0
});

// Enhanced validation with better error messages
if (!supabaseUrl) {
  console.error('❌ Missing VITE_SUPABASE_URL environment variable');
  console.error('💡 Please add VITE_SUPABASE_URL to your .env file');
}

if (!supabaseAnonKey) {
  console.error('❌ Missing VITE_SUPABASE_ANON_KEY environment variable');
  console.error('💡 Please add VITE_SUPABASE_ANON_KEY to your .env file');
}

// Only validate format if variables exist
if (supabaseUrl && (!supabaseUrl.startsWith('https://') || !supabaseUrl.includes('.supabase.co'))) {
  console.error('❌ Invalid Supabase URL format:', supabaseUrl);
  console.error('💡 URL should be in format: https://your-project.supabase.co');
}

if (supabaseAnonKey && (supabaseAnonKey.length < 50 || !supabaseAnonKey.startsWith('eyJ'))) {
  console.error('❌ Invalid Supabase anon key format');
  console.error('💡 Key should start with "eyJ" and be longer than 50 characters');
}

// Create client with fallback values to prevent crashes
const clientUrl = supabaseUrl || 'https://placeholder.supabase.co';
const clientKey = supabaseAnonKey || 'placeholder-key';

export const supabase = createClient<Database>(clientUrl, clientKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
    debug: import.meta.env.MODE === 'development'
  },
  global: {
    headers: {
      'X-Client-Info': 'freelanceflow-web',
      'X-Client-Version': '1.0.0'
    },
    fetch: (url, options = {}) => {
      console.log('🌐 Supabase fetch request:', { url: url.toString(), method: options.method || 'GET' });
      return fetch(url, {
        ...options,
        signal: AbortSignal.timeout(8000), // 8 second timeout for all requests
      });
    }
  },
  db: {
    schema: 'public'
  },
  realtime: {
    params: {
      eventsPerSecond: 10
    }
  }
});

// Enhanced connection monitoring
let connectionAttempts = 0;
let lastConnectionCheck = 0;
let connectionStatus: 'unknown' | 'connected' | 'failed' | 'misconfigured' = 'unknown';
let lastError: string | null = null;

// Check if configuration is valid
const isConfigurationValid = () => {
  const isValid = supabaseUrl && 
         supabaseAnonKey && 
         supabaseUrl.startsWith('https://') && 
         supabaseUrl.includes('.supabase.co') &&
         supabaseAnonKey.length > 50 && 
         supabaseAnonKey.startsWith('eyJ');
  
  console.log('🔍 Configuration validation:', {
    hasUrl: !!supabaseUrl,
    hasKey: !!supabaseAnonKey,
    urlValid: supabaseUrl?.startsWith('https://') && supabaseUrl?.includes('.supabase.co'),
    keyValid: supabaseAnonKey?.length > 50 && supabaseAnonKey?.startsWith('eyJ'),
    isValid
  });
  
  return isValid;
};

// Test connection with enhanced logging and error handling
const testConnection = async (timeoutMs: number = 6000) => {
  const startTime = Date.now();
  connectionAttempts++;
  
  console.log(`🔄 Testing Supabase connection (attempt ${connectionAttempts}) with ${timeoutMs}ms timeout...`);
  
  // Check configuration first
  if (!isConfigurationValid()) {
    connectionStatus = 'misconfigured';
    lastError = 'Invalid or missing Supabase configuration';
    console.warn('⚠️ Supabase configuration is invalid - skipping connection test');
    return false;
  }
  
  try {
    // Create a timeout promise that rejects
    const timeoutPromise = new Promise<never>((_, reject) => {
      const timeoutId = setTimeout(() => {
        console.error(`⏰ Connection timeout after ${timeoutMs / 1000} seconds`);
        reject(new Error(`Connection timeout after ${timeoutMs / 1000} seconds`));
      }, timeoutMs);
      
      // Clear timeout if the promise resolves first
      return timeoutId;
    });
    
    // Use a simpler query that's less likely to fail
    console.log('📡 Attempting database query...');
    const connectionPromise = supabase
      .from('users')
      .select('count')
      .limit(1)
      .maybeSingle()
      .then((result) => {
        console.log('📊 Database query result:', { 
          error: result.error?.message || null, 
          hasData: !!result.data,
          status: result.status 
        });
        return result;
      });
    
    const { error } = await Promise.race([connectionPromise, timeoutPromise]);
    
    const duration = Date.now() - startTime;
    lastConnectionCheck = Date.now();
    
    if (error) {
      connectionStatus = 'failed';
      lastError = error.message;
      
      console.warn('⚠️ Supabase connection failed:', {
        message: error.message,
        code: error.code,
        duration: `${duration}ms`,
        hint: error.hint || 'No hint available'
      });
      
      return false;
    }
    
    connectionStatus = 'connected';
    lastError = null;
    console.log(`✅ Supabase connection successful (${duration}ms)`);
    return true;
  } catch (error) {
    const duration = Date.now() - startTime;
    connectionStatus = 'failed';
    lastError = error instanceof Error ? error.message : 'Unknown error';
    
    console.warn('⚠️ Supabase connection error:', {
      message: error instanceof Error ? error.message : 'Unknown error',
      duration: `${duration}ms`,
      attempts: connectionAttempts,
      type: error instanceof Error ? error.constructor.name : 'Unknown'
    });
    
    return false;
  }
};

// Initialize connection status based on configuration
if (isConfigurationValid()) {
  console.log('🚀 Configuration is valid - connection testing available');
  connectionStatus = 'unknown';
  
  // Test connection in background without blocking app startup
  setTimeout(() => {
    console.log('🔄 Starting background connection test...');
    testConnection(6000).then((success) => {
      console.log('🎯 Background connection test result:', success);
    }).catch((error) => {
      console.error('💥 Background connection test failed:', error);
      // Don't throw - just log the error
    });
  }, 1000); // Delay initial test by 1 second to allow app to load
} else {
  console.warn('⚠️ Supabase configuration is invalid or missing. Please check your .env file.');
  connectionStatus = 'misconfigured';
}

// Add enhanced error handling for auth state changes
supabase.auth.onAuthStateChange((event, session) => {
  console.log(`🔐 Auth event: ${event}`, {
    hasSession: !!session,
    userId: session?.user?.id,
    timestamp: new Date().toISOString(),
    sessionExpiry: session?.expires_at ? new Date(session.expires_at * 1000).toISOString() : null
  });
  
  // Handle token refresh failures gracefully
  if (event === 'TOKEN_REFRESHED' && !session) {
    console.warn('⚠️ Token refresh failed - user may need to re-authenticate');
    connectionStatus = 'failed';
    lastError = 'Token refresh failed';
  }
  
  // Log sign out events
  if (event === 'SIGNED_OUT') {
    console.log('👋 User signed out');
  }
  
  // Log sign in events
  if (event === 'SIGNED_IN') {
    console.log('👤 User signed in successfully');
  }
});

// Session helper with timeout wrapper
export const getSessionWithTimeout = async (timeoutMs: number = 8000) => {
  console.log('🔍 Getting session with timeout wrapper...');
  
  if (!isConfigurationValid()) {
    throw new Error('Supabase configuration is invalid or missing');
  }
  
  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(() => {
      console.error(`⏰ Session fetch timeout after ${timeoutMs / 1000} seconds`);
      reject(new Error(`Session fetch timeout after ${timeoutMs / 1000} seconds`));
    }, timeoutMs);
  });
  
  const sessionPromise = supabase.auth.getSession().then((result) => {
    console.log('📊 Session fetch result:', {
      hasSession: !!result.data.session,
      hasUser: !!result.data.session?.user,
      error: result.error?.message || null,
      userId: result.data.session?.user?.id || null
    });
    return result;
  });
  
  try {
    const result = await Promise.race([sessionPromise, timeoutPromise]);
    return result;
  } catch (error) {
    console.error('🚨 Session fetch failed:', error);
    throw error;
  }
};

// Auth state listener helper
export const createAuthStateListener = (callback: (event: string, session: any) => void) => {
  console.log('🎧 Setting up auth state listener...');
  
  const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
    console.log(`🔄 Auth state change: ${event}`, {
      hasSession: !!session,
      userId: session?.user?.id,
      timestamp: new Date().toISOString()
    });
    
    callback(event, session);
  });
  
  return subscription;
};

// Export connection test function for manual use
export const testSupabaseConnection = async (timeoutMs: number = 6000) => {
  if (!isConfigurationValid()) {
    throw new Error('Supabase configuration is invalid or missing');
  }
  return testConnection(timeoutMs);
};

// Export a function to get connection status
export const getConnectionStatus = () => ({
  status: connectionStatus,
  lastCheck: lastConnectionCheck,
  attempts: connectionAttempts,
  timeSinceLastCheck: Date.now() - lastConnectionCheck,
  lastError,
  isConfigured: isConfigurationValid()
});

// Export a function to reset connection state
export const resetConnectionState = () => {
  connectionAttempts = 0;
  connectionStatus = 'unknown';
  lastConnectionCheck = 0;
  lastError = null;
  console.log('🔄 Connection state reset');
};

// Export configuration check
export const checkConfiguration = () => ({
  hasUrl: !!supabaseUrl,
  hasKey: !!supabaseAnonKey,
  urlValid: supabaseUrl?.startsWith('https://') && supabaseUrl?.includes('.supabase.co'),
  keyValid: supabaseAnonKey?.length > 50 && supabaseAnonKey?.startsWith('eyJ'),
  isValid: isConfigurationValid()
});

// Manual session check function for debugging
export const manualSessionCheck = async () => {
  console.log('🧪 Manual session check initiated...');
  try {
    const startTime = Date.now();
    const { data, error } = await supabase.auth.getSession();
    const duration = Date.now() - startTime;
    
    console.log('🧪 Manual session check result:', {
      hasSession: !!data.session,
      hasUser: !!data.session?.user,
      error: error?.message || null,
      duration: `${duration}ms`,
      userId: data.session?.user?.id || null
    });
    
    return { data, error, duration };
  } catch (error) {
    console.error('🧪 Manual session check failed:', error);
    throw error;
  }
};