// Perfil de app web: sin barra lateral ni barra de direcciones, como el modo
// app de Chromium, y con las extensiones activas desde el principio.
user_pref("zen.welcome-screen.seen", true);
user_pref("zen.view.compact.enable-at-startup", true);
user_pref("zen.view.compact.hide-tabbar", true);
user_pref("zen.view.compact.hide-toolbar", true);
user_pref("zen.view.compact.show-sidebar-and-toolbar-on-hover", false);
user_pref("zen.view.compact.show-background-tab-toast", false);
user_pref("browser.startup.page", 0);
user_pref("browser.tabs.closeWindowWithLastTab", true);
user_pref("extensions.autoDisableScopes", 0);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("zen.theme.disable-lightweight", false);
