package com.psmyles.inkframe

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin

/**
 * inkframe://supabase-oauth?… from the browser ("Connect Supabase"), in place of
 * flutter_web_auth_2's CallbackActivity. Browsers without Chrome's Auth Tab (Firefox, for
 * one) open their tab in the app's task but send this link to a new task, where the
 * plugin's activity can't reach the tab: the app got the code, but the tab stayed on top
 * showing "Returning to Ink Frame…". This hands the link to the plugin the same way, then
 * brings the app's task back with CLEAR_TOP, which closes the tab above the app.
 */
class OAuthCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent?.data
        val scheme = url?.scheme
        if (scheme != null) FlutterWebAuth2Plugin.callbacks.remove(scheme)?.success(url.toString())
        // MainActivity has no task affinity, so NEW_TASK finds its task by the activity.
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        finish()
    }
}
