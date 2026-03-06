/**
 * TalkClaw Widget Bridge — v1.0 (Stub)
 *
 * Provides the TalkClaw.* API surface for widget JavaScript.
 * Full implementation comes in Phase 4 (iOS WKScriptMessageHandler).
 * For now, methods log to console so widgets can be developed and tested.
 */
(function() {
    'use strict';

    const vars = window.TALKCLAW_VARS || {};

    window.TalkClaw = {
        /** Render variables injected by the server */
        vars: vars,

        /**
         * Send a text message to the chat session that created this widget.
         * @param {string} message - The message text
         */
        sendMessage: function(message) {
            console.log('[TalkClaw.sendMessage]', message);
            postToSwift('sendMessage', { message: message });
        },

        /**
         * Send a structured event to the chat session.
         * @param {string} type - Event type (e.g. 'widget_error', 'widget_action')
         * @param {object} data - Event payload
         */
        sendStructured: function(type, data) {
            console.log('[TalkClaw.sendStructured]', type, data);
            postToSwift('sendStructured', { type: type, data: data });
        },

        /**
         * Update render variables on the server.
         * @param {object} newVars - Key-value pairs to merge
         */
        setVars: function(newVars) {
            console.log('[TalkClaw.setVars]', newVars);
            Object.assign(vars, newVars);
            postToSwift('setVars', { vars: newVars });
        },

        /**
         * Request this widget be pinned to the Dashboard tab.
         * @param {number} [colSpan=1] - Column span (1 = half, 2 = full)
         */
        pinToDashboard: function(colSpan) {
            console.log('[TalkClaw.pinToDashboard]', colSpan || 1);
            postToSwift('pinToDashboard', { colSpan: colSpan || 1 });
        },

        /**
         * Dismiss/collapse this widget in the chat view.
         */
        dismiss: function() {
            console.log('[TalkClaw.dismiss]');
            postToSwift('dismiss', {});
        },

        /**
         * Report the widget's content height to the iOS host for auto-sizing.
         * Called automatically on load and resize; widgets can call manually.
         */
        reportHeight: function() {
            var height = document.documentElement.scrollHeight;
            postToSwift('reportHeight', { height: height });
        },

        /**
         * Standard error handler. Renders an inline error card and optionally
         * reports to the agent.
         * @param {Error|string} error - The error
         * @param {string} [context] - What was being attempted
         */
        handleError: function(error, context) {
            var msg = error instanceof Error ? error.message : String(error);
            console.error('[TalkClaw.handleError]', context || '', msg);

            // Create error state UI
            var root = document.getElementById('root');
            if (root) {
                var errorDiv = document.createElement('div');
                errorDiv.className = 'tc-error-state';
                errorDiv.innerHTML =
                    '<div class="tc-error-title">' + escapeHtml(context || 'Widget Error') + '</div>' +
                    '<div>' + escapeHtml(msg) + '</div>' +
                    '<div class="tc-error-actions">' +
                        '<button class="tc-btn tc-btn-secondary" onclick="location.reload()">Retry</button>' +
                        '<button class="tc-btn tc-btn-ghost" onclick="TalkClaw.sendStructured(\'widget_error\', {error: \'' + escapeHtml(msg) + '\', context: \'' + escapeHtml(context || '') + '\'})">Report to Agent</button>' +
                    '</div>';
                root.appendChild(errorDiv);
            }
        }
    };

    // Post message to Swift WKScriptMessageHandler (Phase 4 wiring)
    function postToSwift(action, payload) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.talkclaw) {
            window.webkit.messageHandlers.talkclaw.postMessage({
                action: action,
                payload: payload
            });
        }
    }

    function escapeHtml(str) {
        var div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    // Auto-report height on load and resize
    window.addEventListener('load', function() {
        TalkClaw.reportHeight();
    });

    window.addEventListener('resize', function() {
        TalkClaw.reportHeight();
    });

    // Fetch interceptor for transparent 401 recovery (Phase 3 wiring)
    var originalFetch = window.fetch;
    window.fetch = function() {
        var args = arguments;
        return originalFetch.apply(this, args).then(function(response) {
            if (response.status === 401) {
                console.log('[TalkClaw] 401 received, requesting session refresh...');
                // Phase 3: post refreshSession to Swift, await new cookie, retry
                return response;
            }
            return response;
        });
    };

})();
