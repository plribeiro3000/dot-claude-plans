# SOURCE: lharries/whatsapp-mcp — whatsapp-mcp-server/main.py
# Cloned from https://github.com/lharries/whatsapp-mcp at /tmp/whatsapp-mcp-fix (2026-05-27)
#
# Lines 1-16 — module imports, FastMCP initialization, and the full tool import block
# This block confirms that 12 functions are imported from whatsapp.py and registered as MCP tools
# (verified: 12 @mcp.tool() decorators in the file, one per imported function)

from typing import List, Dict, Any, Optional
from mcp.server.fastmcp import FastMCP
from whatsapp import (
    search_contacts as whatsapp_search_contacts,
    list_messages as whatsapp_list_messages,
    list_chats as whatsapp_list_chats,
    get_chat as whatsapp_get_chat,
    get_direct_chat_by_contact as whatsapp_get_direct_chat_by_contact,
    get_contact_chats as whatsapp_get_contact_chats,
    get_last_interaction as whatsapp_get_last_interaction,
    get_message_context as whatsapp_get_message_context,
    send_message as whatsapp_send_message,
    send_file as whatsapp_send_file,
    send_audio_message as whatsapp_audio_voice_message,
    download_media as whatsapp_download_media
)

# Initialize FastMCP server
mcp = FastMCP("whatsapp")
