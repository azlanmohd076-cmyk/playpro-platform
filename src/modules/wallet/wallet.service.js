/*
 * PlayPro Model 6 — Wallet Engine & Assessment Ledger Service
 * Pure service layer only. Not connected to legacy public/index.html yet.
 *
 * Responsibility:
 * - Read wallet balance through Supabase RLS-safe queries.
 * - Read immutable ledger history from wallet_transactions.
 * - Call controlled PostgreSQL RPC process_assessment_payment(...).
 * - Never insert/update wallet or ledger rows directly from frontend.
 */
(function attachWalletService(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Wallet = bridge.Wallet || {};

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function hasSupabaseClient() {
    var supabase = getSupabaseClient();
    return !!(supabase && typeof supabase.from === 'function');
  }

  function normalizeAmount(value) {
    var n = Number(value);
    return Number.isFinite(n) ? n : 0;
  }

  function safeErrorMessage(error) {
    if (!error) return 'UNKNOWN_ERROR';
    return error.message || error.details || error.hint || String(error);
  }

  function makeFail(reason, extra) {
    return Object.assign({ ok: false, reason: reason }, extra || {});
  }

  var WalletService = {
    /**
     * Mengambil baki wallet milik ejen/assessor berdasarkan profile_id.
     * RLS di DB memastikan user hanya boleh membaca wallet miliknya sendiri.
     *
     * @param {string} profileId - UUID profiles.id ejen/assessor.
     * @returns {Promise<{ok:boolean, reason:string, data:Object|null}>}
     */
    async getWalletBalance(profileId) {
      try {
        if (!profileId) {
          return makeFail('PROFILE_ID_TIDAK_LENGKAP', { data: null });
        }

        if (!hasSupabaseClient()) {
          return makeFail('SUPABASE_CLIENT_NOT_READY', { data: null });
        }

        var supabase = getSupabaseClient();
        var result = await supabase
          .from('agent_wallets')
          .select('id,profile_id,organization_id,wallet_code,status,currency,available_balance,pending_balance,lifetime_earned,lifetime_paid_out,updated_at')
          .eq('profile_id', profileId)
          .eq('status', 'active')
          .order('created_at', { ascending: true })
          .limit(1)
          .maybeSingle();

        if (result.error) throw result.error;

        if (!result.data) {
          return makeFail('WALLET_BELUM_WUJUD', { data: null });
        }

        var wallet = result.data;
        return {
          ok: true,
          reason: 'WALLET_FOUND',
          data: {
            walletId: wallet.id,
            profileId: wallet.profile_id,
            organizationId: wallet.organization_id,
            walletCode: wallet.wallet_code,
            status: wallet.status,
            currency: wallet.currency || 'MYR',
            availableBalance: normalizeAmount(wallet.available_balance),
            pendingBalance: normalizeAmount(wallet.pending_balance),
            lifetimeEarned: normalizeAmount(wallet.lifetime_earned),
            lifetimePaidOut: normalizeAmount(wallet.lifetime_paid_out),
            updatedAt: wallet.updated_at
          }
        };
      } catch (err) {
        console.error('Ralat Wallet Balance Engine:', err);
        return makeFail('RALAT_SEMAKAN_WALLET', {
          data: null,
          error: safeErrorMessage(err)
        });
      }
    },

    /**
     * Mengambil sejarah ledger wallet terbaru dahulu.
     * Uses DB index: idx_model6_wallet_tx_wallet_created_at.
     *
     * @param {string} walletId - UUID agent_wallets.id.
     * @param {Object} options - Optional: { limit:number }.
     * @returns {Promise<{ok:boolean, reason:string, data:Array}>}
     */
    async getTransactionHistory(walletId, options) {
      try {
        if (!walletId) {
          return makeFail('WALLET_ID_TIDAK_LENGKAP', { data: [] });
        }

        if (!hasSupabaseClient()) {
          return makeFail('SUPABASE_CLIENT_NOT_READY', { data: [] });
        }

        var limit = Number(options && options.limit ? options.limit : 50);
        if (!Number.isFinite(limit) || limit < 1) limit = 50;
        if (limit > 200) limit = 200;

        var supabase = getSupabaseClient();
        var result = await supabase
          .from('wallet_transactions')
          .select('id,wallet_id,type,status,amount,currency,gross_amount,playpro_net_amount,commission_amount,player_id,organization_id,related_passport_id,external_reference,description,metadata,posted_at,created_at')
          .eq('wallet_id', walletId)
          .order('created_at', { ascending: false })
          .limit(limit);

        if (result.error) throw result.error;

        return {
          ok: true,
          reason: 'TRANSACTION_HISTORY_FOUND',
          data: result.data || []
        };
      } catch (err) {
        console.error('Ralat Wallet Ledger Engine:', err);
        return makeFail('RALAT_SEMAKAN_LEDGER', {
          data: [],
          error: safeErrorMessage(err)
        });
      }
    },

    /**
     * Wrapper RPC untuk process_assessment_payment.
     * This is the only frontend-accessible path for assessment payment flow.
     * Actual wallet mutation happens inside PostgreSQL SECURITY DEFINER RPC.
     *
     * @param {string} playerId - UUID pemain.
     * @param {string} assessorId - UUID profiles.id assessor/ejen.
     * @returns {Promise<{ok:boolean, reason:string, data:Object|null}>}
     */
    async processAssessmentPayment(playerId, assessorId) {
      try {
        if (!playerId || !assessorId) {
          return makeFail('PARAMETER_PAYMENT_TIDAK_LENGKAP', { data: null });
        }

        var supabase = getSupabaseClient();
        if (!supabase || typeof supabase.rpc !== 'function') {
          return makeFail('SUPABASE_RPC_NOT_READY', { data: null });
        }

        var result = await supabase.rpc('process_assessment_payment', {
          p_player_id: playerId,
          p_assessor_id: assessorId
        });

        if (result.error) {
          var msg = safeErrorMessage(result.error);
          var code = result.error.code || 'RPC_ERROR';

          console.error('Ralat RPC process_assessment_payment:', result.error);

          return makeFail('RPC_PROCESS_ASSESSMENT_PAYMENT_FAILED', {
            data: null,
            error: msg,
            code: code
          });
        }

        return {
          ok: true,
          reason: 'ASSESSMENT_PAYMENT_PROCESSED',
          data: result.data || null
        };
      } catch (err) {
        console.error('Ralat Assessment Payment RPC Wrapper:', err);
        return makeFail('RALAT_RPC_PAYMENT_SYSTEM', {
          data: null,
          error: safeErrorMessage(err)
        });
      }
    }
  };

  bridge.Wallet = Object.assign({}, bridge.Wallet, WalletService);
})(typeof window !== 'undefined' ? window : globalThis);
