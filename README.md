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
2. `./zulip_archive.sh path_to_zuliprc`
3. Press tab to select streams downloaded.
4. Open index.html in browser.
