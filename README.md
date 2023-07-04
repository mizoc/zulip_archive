# zulip_archive
Simple bash script to archive zulip as static html.  
Most of the HTML/CSS code are copy of https://github.com/felixrieseberg/slack-archive

### Requirements
- curl
- pup
- jq
- fzf

### Usage
1. Download your zuliprc.
2. `curl -s https://raw.githubusercontent.com/mizoc/zulip_archive/main/zulip_save.sh | bash -s path_to_your_zuliprc`
3. Press tab to select streams to download.
4. Open index.html in browser.
