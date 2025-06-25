import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { User as SupabaseUser } from '@supabase/supabase-js';
import { supabase, getConnectionStatus } from '../lib/supabase';
import { User } from '../types';

interface AuthContextType {
  user: User | null;
  supabaseUser: SupabaseUser | null;
  login: (email: string, password: string) => Promise<boolean>;
  signup: (name: string, email: string, password: string, role: 'client' | 'worker') => Promise<boolean>;
  logout: () => Promise<void>;
  isLoading: boolean;
  updateProfile: (updates: Partial<User>) => Promise<boolean>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [supabaseUser, setSupabaseUser] = useState<SupabaseUser | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const clearSession = async () => {
    console.log('AuthProvider: Clearing session...');
    setUser(null);
    setSupabaseUser(null);
    setIsLoading(false);
  };

  const handleAuthError = (error: any) => {
    console.error('AuthProvider: Auth error:', error);
    
    // Check for token-related errors
    if (error?.message?.includes('refresh_token_not_found') || 
        error?.message?.includes('Invalid Refresh Token') ||
        error?.message?.includes('JWT') ||
        error?.code === 'invalid_grant') {
      console.log('AuthProvider: Token error detected, clearing session...');
      clearSession();
      return true;
    }
    
    return false;
  };

  useEffect(() => {
    console.log('AuthProvider: Initializing with enhanced session handling...');
    
    let mounted = true;
    
    // Enhanced initialization with better error handling
    const initializeAuth = async () => {
      try {
        // Check if Supabase is properly configured first
        const connectionStatus = getConnectionStatus();
        if (!connectionStatus.isConfigured) {
          console.warn('AuthProvider: Supabase not configured, app will load without auth');
          if (mounted) {
            setIsLoading(false);
          }
          return;
        }

        console.log('AuthProvider: Supabase configured, checking session...');
        
        // Try to get the current session with timeout
        const sessionPromise = supabase.auth.getSession();
        const timeoutPromise = new Promise<never>((_, reject) => 
          setTimeout(() => reject(new Error('Session check timeout')), 30000)
        );
        
        const { data: { session }, error } = await Promise.race([
          sessionPromise,
          timeoutPromise
        ]);

        if (error) {
          console.error('AuthProvider: Session check error:', error);
          if (!handleAuthError(error)) {
            console.log('AuthProvider: Non-token error, continuing without session...');
          }
          if (mounted) {
            setIsLoading(false);
          }
          return;
        }

        if (mounted) {
          setSupabaseUser(session?.user ?? null);
          
          if (session?.user) {
            console.log('AuthProvider: Session found, fetching profile...');
            await fetchUserProfile(session.user.id);
          } else {
            console.log('AuthProvider: No session found');
            setUser(null);
            setIsLoading(false);
          }
        }
      } catch (error) {
        console.error('AuthProvider: Initialization error:', error);
        if (mounted) {
          // Always allow app to continue loading
          console.log('AuthProvider: App will continue loading despite auth error...');
          setUser(null);
          setSupabaseUser(null);
          setIsLoading(false);
        }
      }
    };

    initializeAuth();

    // Listen for auth changes with enhanced error handling
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(async (event, session) => {
      if (!mounted) return;
      
      console.log('AuthProvider: Auth state changed', { 
        event, 
        hasSession: !!session,
        userId: session?.user?.id,
        timestamp: new Date().toISOString()
      });
      
      try {
        // Handle specific events
        if (event === 'SIGNED_OUT') {
          console.log('AuthProvider: User signed out');
          setUser(null);
          setSupabaseUser(null);
          setIsLoading(false);
          return;
        }
        
        if (event === 'SIGNED_IN') {
          console.log('AuthProvider: User signed in, fetching profile...');
          setSupabaseUser(session?.user ?? null);
          if (session?.user) {
            await fetchUserProfile(session.user.id);
          } else {
            console.warn('AuthProvider: SIGNED_IN event but no session user found');
            setIsLoading(false);
          }
          return;
        }
        
        if (event === 'TOKEN_REFRESHED') {
          console.log('AuthProvider: Token refreshed successfully');
          if (!session) {
            console.log('AuthProvider: Token refresh failed, clearing session');
            await clearSession();
            return;
          }
        }
        
        // Handle other session changes gracefully
        setSupabaseUser(session?.user ?? null);
        
        if (session?.user) {
          console.log('AuthProvider: Session change - fetching profile...');
          await fetchUserProfile(session.user.id);
        } else {
          console.log('AuthProvider: Session change - clearing user');
          setUser(null);
          setIsLoading(false);
        }
      } catch (error) {
        console.error('AuthProvider: Auth state change error:', error);
        if (!handleAuthError(error)) {
          console.log('AuthProvider: Non-token error in auth state change, continuing...');
          setIsLoading(false);
        }
      }
    });

    return () => {
      mounted = false;
      console.log('AuthProvider: Cleaning up auth subscription');
      subscription.unsubscribe();
    };
  }, []);

  const fetchUserProfile = async (userId: string) => {
    console.log('AuthProvider: Fetching profile for user:', userId);
    
    try {
      // Use maybeSingle() instead of single() to handle cases where no user exists
      const { data, error } = await supabase
        .from('users')
        .select('*')
        .eq('id', userId)
        .maybeSingle();

      if (error) {
        console.error('AuthProvider: Error fetching user profile:', error);
        
        // Handle auth errors
        if (handleAuthError(error)) return;
        
        // For other errors, don't fail completely
        console.warn('AuthProvider: Profile fetch failed, but continuing...');
        setIsLoading(false);
        return;
      }

      // If no user profile exists, create one
      if (!data) {
        console.log('AuthProvider: User not found in users table, creating profile...');
        
        const { data: authUser } = await supabase.auth.getUser();
        if (authUser.user) {
          const { error: insertError } = await supabase
            .from('users')
            .insert([{
              id: authUser.user.id,
              email: authUser.user.email || '',
              name: authUser.user.user_metadata?.name || '',
              role: 'worker', // Default role
              rating: 0,
              wallet_balance: 0,
              skills: [],
              tier: 'bronze',
              onboarding_completed: false,
            }]);
          
          // Handle duplicate key error gracefully (code 23505)
          if (insertError && insertError.code !== '23505') {
            console.error('AuthProvider: Error creating user profile:', insertError);
            // Don't fail completely, just set loading to false
            setIsLoading(false);
            return;
          } else if (insertError?.code === '23505') {
            console.log('AuthProvider: User profile already exists (duplicate key), refetching...');
          } else {
            console.log('AuthProvider: Created new user profile successfully');
          }
          
          // Retry fetching the profile after creation or if duplicate key error
          await fetchUserProfile(userId);
          return;
        }
      } else {
        // User profile exists, set the user data
        console.log('AuthProvider: Successfully fetched user profile:', {
          id: data.id,
          email: data.email,
          role: data.role,
          name: data.name
        });
        
        setUser({
          id: data.id,
          role: data.role,
          name: data.name || '',
          email: data.email,
          skills: data.skills || [],
          rating: data.rating || 0,
          walletBalance: data.wallet_balance || 0,
          avatar: data.avatar_url || undefined,
          tier: data.tier || 'bronze',
          onboarding_completed: data.onboarding_completed || false,
        });
      }
    } catch (error) {
      console.error('AuthProvider: Error in fetchUserProfile:', error);
      
      // Handle auth errors
      if (!handleAuthError(error)) {
        // For non-auth errors, still set loading to false
        console.log('AuthProvider: Profile fetch error, but continuing app load...');
        setIsLoading(false);
      }
    } finally {
      console.log('AuthProvider: Setting loading to false after profile fetch');
      setIsLoading(false);
    }
  };

  const login = async (email: string, password: string): Promise<boolean> => {
    console.log('AuthProvider: Attempting login for:', email);
    
    try {
      // Check if Supabase is configured
      const connectionStatus = getConnectionStatus();
      if (!connectionStatus.isConfigured) {
        console.error('AuthProvider: Supabase not configured');
        return false;
      }

      // Clear any existing session first
      await supabase.auth.signOut();
      
      const { data, error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (error) {
        console.error('AuthProvider: Login error:', error);
        return false;
      }
      
      if (data.user && data.session) {
        console.log('AuthProvider: Login successful');
        // Don't set loading here, let the auth state change handle it
        return true;
      }
      
      console.log('AuthProvider: Login failed - no user or session returned');
      return false;
    } catch (error) {
      console.error('AuthProvider: Login failed:', error);
      return false;
    }
  };

  const signup = async (name: string, email: string, password: string, role: 'client' | 'worker'): Promise<boolean> => {
    console.log('AuthProvider: Attempting signup for:', email, 'as', role);
    
    try {
      // Check if Supabase is configured
      const connectionStatus = getConnectionStatus();
      if (!connectionStatus.isConfigured) {
        console.error('AuthProvider: Supabase not configured');
        return false;
      }

      // Sign up with Supabase Auth
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: {
          data: {
            name: name.trim()
          }
        }
      });

      if (authError) {
        console.error('AuthProvider: Signup auth error:', authError);
        return false;
      }

      if (authData.user) {
        console.log('AuthProvider: Auth signup successful, creating profile...');
        
        // Create user profile
        const { error: profileError } = await supabase
          .from('users')
          .insert([{
            id: authData.user.id,
            email: email.trim(),
            name: name.trim(),
            role,
            rating: 0,
            wallet_balance: role === 'client' ? 5000 : 0,
            skills: role === 'worker' ? [] : null,
            tier: role === 'worker' ? 'bronze' : null,
            onboarding_completed: false,
          }]);

        // Handle duplicate key error gracefully (code 23505)
        if (profileError && profileError.code !== '23505') {
          console.error('AuthProvider: Profile creation error:', profileError);
          return false;
        } else if (profileError?.code === '23505') {
          console.log('AuthProvider: User profile already exists during signup (duplicate key)');
        } else {
          console.log('AuthProvider: Profile created successfully during signup');
        }
        
        console.log('AuthProvider: Signup completed successfully');
        return true;
      }
      
      console.log('AuthProvider: Signup failed - no user returned');
      return false;
    } catch (error) {
      console.error('AuthProvider: Signup error:', error);
      return false;
    }
  };

  const logout = async (): Promise<void> => {
    console.log('AuthProvider: Logging out...');
    
    try {
      // Sign out from Supabase
      const { error } = await supabase.auth.signOut();
      
      if (error) {
        console.error('AuthProvider: Logout error:', error);
      }
      
      // Clear local state
      await clearSession();
      console.log('AuthProvider: Logout completed');
    } catch (error) {
      console.error('AuthProvider: Logout error:', error);
      // Even if logout fails, clear local state
      await clearSession();
    }
  };

  const updateProfile = async (updates: Partial<User>): Promise<boolean> => {
    if (!user) {
      console.log('AuthProvider: Cannot update profile - no user');
      return false;
    }

    console.log('AuthProvider: Updating profile:', updates);

    try {
      const updateData: any = {};
      
      if (updates.name !== undefined) updateData.name = updates.name;
      if (updates.skills !== undefined) updateData.skills = updates.skills;
      if (updates.avatar !== undefined) updateData.avatar_url = updates.avatar;
      if (updates.onboarding_completed !== undefined) updateData.onboarding_completed = updates.onboarding_completed;

      const { error } = await supabase
        .from('users')
        .update(updateData)
        .eq('id', user.id);

      if (error) {
        console.error('AuthProvider: Profile update error:', error);
        return false;
      }

      setUser({ ...user, ...updates });
      console.log('AuthProvider: Profile updated successfully');
      return true;
    } catch (error) {
      console.error('AuthProvider: Profile update failed:', error);
      return false;
    }
  };

  console.log('AuthProvider: Current state', { 
    hasUser: !!user, 
    hasSupabaseUser: !!supabaseUser, 
    isLoading,
    userRole: user?.role,
    timestamp: new Date().toISOString()
  });

  return (
    <AuthContext.Provider value={{ 
      user, 
      supabaseUser, 
      login, 
      signup, 
      logout, 
      isLoading, 
      updateProfile 
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}