fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_fxv2_oal 'yes'

title 'GRX Group App'
description 'A group app for lb-phone, with prp group compatibility'
author 'mafiaborn'

client_scripts {
    'client/**/*',
}

server_script 'server/**/*'

shared_scripts {
    '@ox_lib/init.lua',
    'bridge/*.lua'
}

files {
    "ui/dist/**/*"
}

ui_page "ui/dist/index.html"
