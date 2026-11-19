#!/bin/bash

export TELEGRAM_ENV_SET="1"

export DEVELOPMENT_CODE_SIGN_IDENTITY="iPhone Distribution: Digital Fortress LLC (C67CF9S4VU)"
export DISTRIBUTION_CODE_SIGN_IDENTITY="iPhone Distribution: Digital Fortress LLC (C67CF9S4VU)"
export DEVELOPMENT_TEAM="C67CF9S4VU"

export API_ID="8"
export API_HASH="7245de8e747a0d6fbe11f7cc14fcc0bb"

export BUNDLE_ID="org.qxgram.app"
export APP_CENTER_ID="0"
export IS_INTERNAL_BUILD="false"
export IS_APPSTORE_BUILD="true"
export APPSTORE_ID="686449807"
export APP_SPECIFIC_URL_SCHEME="qxgram"
export PREMIUM_IAP_PRODUCT_ID="org.telegram.telegramPremium.monthly"

if [ -z "$BUILD_NUMBER" ]; then
	echo "BUILD_NUMBER is not defined"
	exit 1
fi

export DEVELOPMENT_PROVISIONING_PROFILE_APP="match Development org.qxgram.app"
export DISTRIBUTION_PROVISIONING_PROFILE_APP="match AppStore org.qxgram.app"
export DEVELOPMENT_PROVISIONING_PROFILE_EXTENSION_SHARE="match Development org.qxgram.app.Share"
export DISTRIBUTION_PROVISIONING_PROFILE_EXTENSION_SHARE="match AppStore org.qxgram.app.Share"
export DEVELOPMENT_PROVISIONING_PROFILE_EXTENSION_WIDGET="match Development org.qxgram.app.Widget"
export DISTRIBUTION_PROVISIONING_PROFILE_EXTENSION_WIDGET="match AppStore org.qxgram.app.Widget"
export DEVELOPMENT_PROVISIONING_PROFILE_EXTENSION_NOTIFICATIONSERVICE="match Development org.qxgram.app.NotificationService"
export DISTRIBUTION_PROVISIONING_PROFILE_EXTENSION_NOTIFICATIONSERVICE="match AppStore org.qxgram.app.NotificationService"
export DEVELOPMENT_PROVISIONING_PROFILE_EXTENSION_NOTIFICATIONCONTENT="match Development org.qxgram.app.NotificationContent"
export DISTRIBUTION_PROVISIONING_PROFILE_EXTENSION_NOTIFICATIONCONTENT="match AppStore org.qxgram.app.NotificationContent"
export DEVELOPMENT_PROVISIONING_PROFILE_EXTENSION_INTENTS="match Development org.qxgram.app.SiriIntents"
export DISTRIBUTION_PROVISIONING_PROFILE_EXTENSION_INTENTS="match AppStore org.qxgram.app.SiriIntents"
export DEVELOPMENT_PROVISIONING_PROFILE_WATCH_APP="match Development org.qxgram.app.watchkitapp"
export DISTRIBUTION_PROVISIONING_PROFILE_WATCH_APP="match AppStore org.qxgram.app.watchkitapp"
export DEVELOPMENT_PROVISIONING_PROFILE_WATCH_EXTENSION="match Development org.qxgram.app.watchkitapp.watchkitextension"
export DISTRIBUTION_PROVISIONING_PROFILE_WATCH_EXTENSION="match AppStore org.qxgram.app.watchkitapp.watchkitextension"

BUILDBOX_DIR="buildbox"

export CODESIGNING_PROFILES_VARIANT="appstore"

$@
