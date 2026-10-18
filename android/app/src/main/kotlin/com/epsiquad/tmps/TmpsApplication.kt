package com.epsiquad.tmps

import android.app.Application
import com.bbflight.background_downloader.BDPlugin

/**
 * Плагин background_downloader берёт подписи кнопок уведомления («Отменить»,
 * «Пауза», «Продолжить») из ресурсов только в момент, когда к процессу
 * подключается Activity. Если загрузку продолжает фоновый процесс без Activity
 * (приложение закрыли, система перезапустила задачу), подписи пустые или
 * английские. Поэтому кладём русские тексты сразу при создании процесса.
 */
class TmpsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        BDPlugin.notificationButtonText["Cancel"] = getString(R.string.tmps_notif_cancel)
        BDPlugin.notificationButtonText["Pause"] = getString(R.string.tmps_notif_pause)
        BDPlugin.notificationButtonText["Resume"] = getString(R.string.tmps_notif_resume)
    }
}
