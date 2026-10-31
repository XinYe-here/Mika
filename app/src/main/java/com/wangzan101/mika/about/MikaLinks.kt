package com.wangzan101.mika.about

import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.tr
import java.net.URLEncoder

/** Mika 对外的地址都在这里:仓库、问题、作者、检查更新用的两个来源。换地址只改这一处。 */
object MikaLinks {
    // 自维护分支(dsh/main):仓库、检查更新、下载更新都指向我们自己的 fork,
    // 这样「关于 Mika → 有新版本」认的是我们自己发布的 APK,而不是上游。
    const val REPO = "https://github.com/XinYe-here/Mika"
    const val REPO_LABEL = "github.com/XinYe-here/Mika"
    const val README = "$REPO#readme"
    const val RELEASES = "$REPO/releases"
    const val NEW_ISSUE = "$REPO/issues/new"
    const val X = "https://x.com/wangzan101"
    const val X_HANDLE = "@wangzan101"
    const val AUTHOR_WECHAT_ID = "wangzan101"

    /** 让 Mika 替用户发给作者的那句话。 */
    val GROUP_REQUEST: String get() = tr(R.string.group_request)

    /** 关于页「让 Mika 帮我发消息入群」交给 Mika 的原话:按微信号找作者发 [GROUP_REQUEST];找不到就说明还没加好友,不加、不发给别人。 */
    val GROUP_TASK: String get() = tr(R.string.group_task, AUTHOR_WECHAT_ID, GROUP_REQUEST)

    /** 检查更新只问 GitHub 发布页(不登录,每小时有次数限制)。自维护分支指向我们自己的 fork。 */
    const val LATEST_RELEASE_API = "https://api.github.com/repos/XinYe-here/Mika/releases/latest"

    /** 反馈时预先填进问题模板的设备与版本信息。 */
    data class Device(
        val manufacturer: String,
        val model: String,
        val androidRelease: String,
        val sdk: Int,
        val versionName: String,
        val build: String,
    )

    /** 预先填好的问题正文:机型、安卓版本、Mika 版本三行,下面留空几段给用户写。 */
    fun issueBody(d: Device): String {
        val model = if (d.model.startsWith(d.manufacturer, ignoreCase = true)) d.model else "${d.manufacturer} ${d.model}"
        return buildString {
            append(tr(R.string.issue_body, model.trim(), d.androidRelease, d.sdk, d.versionName, d.build))
        }
    }

    /** 新建问题的地址,标题留空、正文预先填好;参数按 URL 编码(空格写成 %20)。 */
    fun issueUrl(d: Device): String = "$NEW_ISSUE?title=&body=${encode(issueBody(d))}"

    private fun encode(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
}
