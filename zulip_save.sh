#!/bin/bash
# Author:mizoc
# License:MIT

test -e "$1" || exit 1
eval `tail -n +2 "$1"` # define $email, $site, $key
QUERY_NUM=500 # number of getting messages per a request
DOMAIN=`echo $site|sed -E 's/^.*(http|https):\/\/([^/]+).*/\2/g'`
mkdir -p $DOMAIN/{raw_json,html,data,avatars}

# Download messages
curl -sSX GET -G ${site}/api/v1/streams -u ${email}:$key | jq -r .streams[].name |fzf --height 50% --layout reverse -m | # Select streams to download
while read STREAM;do
  ANCHOR_COUNT=oldest
  LAST_MSG_ID=`curl -sSX GET -G ${site}/api/v1/messages -u ${email}:$key --data-urlencode anchor=newest  --data-urlencode num_before=1 --data-urlencode num_after=0 --data-urlencode include_anchor=true --data-urlencode client_gravatar=false --data-urlencode narrow="[{\"operand\": \"$STREAM\", \"operator\": \"stream\"}]"|jq .messages[0].id `

  while :;do
      curl -sSX GET -G ${site}/api/v1/messages -u ${email}:$key --data-urlencode anchor=$ANCHOR_COUNT  --data-urlencode num_before=0 --data-urlencode num_after=$QUERY_NUM --data-urlencode include_anchor=true --data-urlencode apply_markdown=true --data-urlencode client_gravatar=false --data-urlencode narrow="[{\"operand\": \"$STREAM\", \"operator\": \"stream\"}]" > $DOMAIN/raw_json/${STREAM}_${ANCHOR_COUNT}.json
      ANCHOR_COUNT=$(( `cat $DOMAIN/raw_json/${STREAM}_${ANCHOR_COUNT}.json|jq .messages[-1].id` + 1 ))
      (( $ANCHOR_COUNT > $LAST_MSG_ID )) && break
  done
done

# Convert json to html
ls $DOMAIN/raw_json |sed 's/_.*//g'|sort|uniq|
while read STREAM;do
test -e $DOMAIN/html/${STREAM}.html && continue # skip streams already downloaded
cat <<HEADER >$DOMAIN/html/${STREAM}.html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charSet="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Zulip</title>
  <link rel="stylesheet" href="style.css" />
</head>
<body>
  <div style="padding-left:10px">
    <div class="header">
      <h1>$STREAM</h1>
      <p class="topic"></p>
    </div>
    <div class="messages-list">
HEADER

jq -s add $DOMAIN/raw_json/${STREAM}_*|sed 's/\\n//g' |jq -r '.messages|sort_by(.timestamp)[]|if .avatar_url==null then .avatar_url="no_image" else .avatar_url = .avatar_url end |[.id, .sender_full_name, .content, .timestamp, .subject, .avatar_url]|@tsv'|
  awk -F "\t" '{printf "<div class=\"message-gutter\" id=\""$1"\"><div class=\"\" data-stringify-ignore=\"true\"><img class=\"avatar\" src=\"../avatars/"; sub(/^.*\//, "", $6); gsub(/=/, "-" , $6); gsub(/&/, "-" , $6);gsub(/\?/, "-" , $6); printf $6".png\" /></div><div class=\"\"><span class=\"sender\"><strong>["$5"]</strong>  "$2"</span><span class=\"timestamp\"><span class=\"c-timestamp__label\">"; "TZ=JST-9 date -d @"$4" +\"%Y/%b/%d %I:%M %p\""|getline date; print date"</span></span><br/><div class=\"text\">"$3"</div></div></div>"}' >>$DOMAIN/html/${STREAM}.html #2>/dev/null
# jq -s add $DOMAIN/raw_json/${STREAM}_*|sed 's/\\n//g' |jq -r '.messages|sort_by(.timestamp)[] |[.id, .sender_full_name, .content, .timestamp, .subject]|@tsv'|
#   awk -F "\t" '{printf "<div class=\"message-gutter\" id=\""$1"\"><div class=\"\" data-stringify-ignore=\"true\"><img class=\"avatar\" src=\"../avatars/"; gsub(/ /, "" , $2); printf $2".png\" /></div><div class=\"\"><span class=\"sender\"><strong>["$5"]</strong>  "$2"</span><span class=\"timestamp\"><span class=\"c-timestamp__label\">"; "TZ=JST-9 date -d @"$4" +\"%Y/%b/%d %I:%M %p\""|getline date; print date"</span></span><br/><div class=\"text\">"$3"</div></div></div>"}' >>$DOMAIN/html/${STREAM}.html #2>/dev/null

# Download attachments
mkdir -p $DOMAIN/data/$STREAM
# sed -E 's%.*(/user_uploads.*)\"><.*%\1%g' $DOMAIN/html/$STREAM.html|/bin/grep user_uploads|
cat <(cat $DOMAIN/html/$STREAM.html|pup 'img' attr{src}text{}) <(cat $DOMAIN/html/$STREAM.html|pup '[class="text"] > p > a attr{href}')|/bin/grep user_uploads|
while read URL;do
  FILE=`basename $URL`
  test -e $DOMAIN/data/$STREAM/$FILE || curl -sSX GET $site`curl -sSX GET -G $site/api/v1$URL -u $email:$key|jq -r .url` -o $DOMAIN/data/$STREAM/$FILE
  sed -i "s%$URL%\.\./data/$STREAM/$FILE%g" $DOMAIN/html/$STREAM.html # link url
done

# FOOTER
cat <<FOOTTER >>$DOMAIN/html/${STREAM}.html
    </div>
    <script>
    var msgLinks=document.getElementsByTagName('a');
    for(var i=0;i<msgLinks.length;i++){msgLinks[i].setAttribute('target','_blank')}
    var msgtag=document.getElementsByClassName('message-gutter');
    var topicDiv=document.getElementsByClassName('topic')[0];
    var sdtag=document.getElementsByClassName('sender');
    var elAll=document.createElement('button');
    elAll.addEventListener('click',function(){
    for(var i=0;i<msgtag.length;i++){msgtag[i].style.display='flex'};
    var element = document.documentElement;
    var bottom = element.scrollHeight - element.clientHeight;
    window.scrollTo({top: bottom, left: 0, behavior: 'smooth'});
    var old=document.querySelector('.selected2'); if(old!=null){old.classList.remove('selected2')}; elAll.classList.add('selected2'); elAll.classList.remove('notSelected2')
    },false);
    elAll.innerText='すべてのトピックを表示';
    elAll.classList.add('topicSwitcher');
    elAll.classList.add('selected2');
    topicDiv.appendChild(elAll);
  window.onload=()=>{var element = document.documentElement;
    var bottom = element.scrollHeight - element.clientHeight;
 window.scrollTo({top: bottom, left: 0, behavior: 'smooth'});}

    var topicList={};//連想配列。何番目のメッセージかも記録。
    for (var i=0;i<sdtag.length;i++){
    var topicI1=sdtag[i].querySelector('strong').innerText;//[トピック名]
    var topicI=topicI1.slice(1,topicI1.length-1);//トピック名
      if(topicList[topicI]==null){topicList[topicI]=[i]}else{topicList[topicI].push(i)}
    }
  var topicNameList=Object.keys(topicList);//トピック名のみ
var tnl2=Object.keys(topicList);//no topicとstream eventを並べ替えた配列
if(topicNameList.indexOf('stream events')>-1){tnl2.splice(topicNameList.indexOf('stream events'),1);tnl2.push('stream events');}
if(topicNameList.indexOf('(no topic)')>-1){tnl2.splice(tnl2.indexOf('(no topic)'),1);tnl2.push('(no topic)');} //トピック名のみ。no topicは最後に。stream eventは最後から2番目に。
  for (var i=0;i<topicNameList.length;i++){
  var el=document.createElement('button');
  el.id='displayTopic'+topicNameList.indexOf(tnl2[i]);//並べ替える前の番号なので注意。iとは別。
  if(tnl2[i]!='(no topic)'){el.innerText=tnl2[i];//ここは並べ替えた後の番号
  }else{el.innerText='トピックなし'}
  el.classList.add('topicSwitcher');
  el.classList.add('notSelected2');
  el.addEventListener('click',disp,false);
topicDiv.appendChild(el);
  }
  function disp(e){
var btnId=e.target.id;var old=document.querySelector('.selected2'); if(old!=null){old.classList.remove('selected2');old.classList.add('notSelected2')}; e.target.classList.add('selected2');e.target.classList.remove('notSelected2');
var targetTopic=topicNameList[Number(btnId.slice(12,btnId.length))];
for (var i=0;i<msgtag.length;i++){
if (topicList[targetTopic].indexOf(i)>-1){msgtag[i].style.display='flex'}else{msgtag[i].style.display='none'}
}
        var element = document.documentElement;
    var bottom = element.scrollHeight - element.clientHeight;
 window.scrollTo({top: bottom, left: 0, behavior: 'smooth'});
}
    </script>
  </div>
</body>
</html>
FOOTTER
done

# Download avatar images
test -e $DOMAIN/avatars/no_image.png || curl -s -o $DOMAIN/avatars/no_image.png https://raw.githubusercontent.com/mizoc/zulip_archive/main/no_image.png
jq -s add $DOMAIN/raw_json/*|sed 's/\\n//g' |jq -r '.messages[].avatar_url'|grep -v null |sort|uniq|
while read URL;do
  # AVATAR_PATH=`echo $URL|sed -E 's%^.*/(.*)\?.*%\1%g'`
  test -e  $DOMAIN/avatars/`basename "$URL"|tr '?&=' -`.png|| curl "$URL" -o $DOMAIN/avatars/`basename "$URL"|tr '?&=' -`.png >/dev/null 2>&1
  # sed -i "s%avatars/https.*$AVATAR_PATH\?.*version=2\.png%../avatars/$AVATAR_PATH.png%g" $DOMAIN/html/*.html # link url
done
# cd $CURRENT_DIR

# Create index.html
cat <<INDEX_HEADER >$DOMAIN/index.html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charSet="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Zulip</title>
  <link rel="stylesheet" href="html/style.css" />
</head>
<body>
  <div id="index">
    <div id="channels">
    <a><img id="realm-logo" src="https://zulipchat.com/static/images/logo/zulip-org-logo.svg?version=0" alt="" class="nav-logo no-drag"></a>
      <p class="section">Streams</p>
      <ul>
INDEX_HEADER

ls $DOMAIN/data |awk '{print "<li><a title=\"" $1 "\" href=\"html/"$1 ".html\" target=\"iframe\"><span># </span><span>" $1 "</span></a></li>"}' >>$DOMAIN/index.html

cat <<INDEX_FOOTER >>$DOMAIN/index.html
      </ul>
    </div>
    <div id="messages"><iframe name="iframe" src="html/`ls $DOMAIN/html/ | sed -n 1p`"></iframe></div>
    <script>
      const urlSearchParams = new URLSearchParams(window.location.search);
            const channelValue = urlSearchParams.get("c");
            const tsValue = urlSearchParams.get("ts");

            if (channelValue) {
              const iframe = document.getElementsByName('iframe')[0]
              iframe.src = "html/" + decodeURIComponent(channelValue) + '.html' + '#' + (tsValue || '');
            }
    </script>
    <script>
    //開いたとき
    var fn1=document.querySelector('iframe').src;
    var fn=decodeURIComponent(fn1.slice(fn1.indexOf('html'),fn1.length));
    var fnl=document.querySelector('a[href="'+fn+'"]');
    var ls=document.querySelectorAll('a[target="iframe"]');
    for(var i=0;i<ls.length;i++){
    ls[i].classList.add('notSelected');
 ls[i].addEventListener('click',function(){var old=document.querySelector('.selected');if(old!=null){old.classList.remove('selected');old.classList.add('notSelected')}this.classList.add('selected');this.classList.remove('notSelected')});
    }
       if(fnl!=null){fnl.classList.add('selected');fnl.classList.remove('notSelected')} //最初に表示されているストリームだけ.selectedを付与し、.notSelectedを削除
    </script>
  </div>
</body>
</html>
INDEX_FOOTER

# Create style.css
cat <<STYLE >$DOMAIN/html/style.css
/* Reset */

/* Box sizing rules */
*,
*::before,
*::after {
  box-sizing: border-box;
}

/* Remove default margin */
body,
h1,
h2,
h3,
h4,
p,
figure,
blockquote,
dl,
dd {
  margin: 0;
}

/* Remove list styles on ul, ol elements with a list role, which suggests default styling will be removed */
ul[role='list'],
ol[role='list'] {
  list-style: none;
}

/* Set core root defaults */
html:focus-within {
  scroll-behavior: smooth;
}

/* Set core body defaults */
body {
  min-height: 100vh;
  text-rendering: optimizeSpeed;
  line-height: 1.5;
}

/* A elements that don't have a class get default styles */
a:not([class]) {
  text-decoration-skip-ink: auto;
}

/* Make images easier to work with */
img,
picture {
  max-width: 100%;
  display: block;
}

/* Inherit fonts for inputs and buttons */
input,
button,
textarea,
select {
  font: inherit;
}

/* Remove all animations, transitions and smooth scroll for people that prefer not to see them */
@media (prefers-reduced-motion: reduce) {
  html:focus-within {
   scroll-behavior: auto;
  }

  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}

/*fontの読み込み削除*/

body, html {
  font-family: 'Lato', sans-serif;
  font-size: 14px;
  color: rgb(29, 28, 29);
  background: #efefef;/*変更*/
}

a {
  color: rgb(18, 100, 163);
}

audio, video {
  max-width: 400px;
}

.messages-list {
  padding-bottom: 20px;
}

.messages-list .avatar {
  height: 36px;
  width: 36px;
  border-radius: 7px;
  margin-right: 10px;
  background: #efefef;

}

.message-gutter {
  display: flex;
  border-bottom: 1px solid #BBB; /*変更 margin削った*/
  padding: 10px; /*変更*/
  scroll-margin-top: 120px;
  background: #fff;/*変更*/
}

.message-gutter:target {
  background-color: #fafafa;
  border: 2px solid #39113E;
  padding: 10px;
  border-radius: 5px;
}

.message-gutter div:first-of-type {
  flex-shrink: 0;
}

.message-gutter > .message-gutter {
  /** i.e. replies in thread. Just here to be easily findable */
}

.sender {
  font-weight: 800;
  margin-right: 10px;
}

.timestamp {
  font-weight: 200;
  font-size: 13px;
  color: rgb(97, 96, 97);
}

.header {
  position: sticky;
  background: hsl(0, 0%, 96%);/*変更*/
  color: #616061;
  top: 0;
  left: 0;
  padding: 10px;
  min-height: 70px;
  border-bottom: 1px solid #E2E2E2;
  box-sizing: border-box;
}

.header h1 {
  font-size: 16px;
  color: #1D1C1D;
  display: inline-block;
}

.header a {
  color: #616061;
}

.header a:active, .header a.current {
  color: #000;
  font-weight: 800;
}

.header .created {
  float: right;
}

.jumper {
  overflow: auto;
  max-width: calc(100vw - 20px);
}

.jumper a {
  margin: 2px;
}

.text {
  overflow-wrap: break-word;
}

.file {
  max-height: 270px;
  margin-right: 10px;
  margin-top: 10px;
  border-radius: 4px;
  border: 1px solid #80808045;
  outline: none;
}

.message_inline_image img{
  width: 150px;
}

#index {
  display: flex;
  height: calc(100vh - 4px);
}

#channels {
  background: #efefef; /*変更*/
  width: 250px;
  color: #000; /*変更*/
  padding-top: 10px;
  overflow: scroll;
  padding-bottom: 20px;
  border-right: 1px solid #ccc;/*変更*/
}

#channels ul {
  margin: 0;
  padding: 0;
  list-style: none;
}

#channels p {
  padding-left: 20px;
}

#channels .section {
  font-weight: 800;
  color: #6d6d6d;/*変更*/
  margin-top: 10px;
}

#channels .section:first-of-type {
  margin-top: 0;
}

#channels a {
  padding: 5px;
  display: block;
  color: hsl(0, 0%, 15%); /*変更*/
  text-decoration: none;
  padding-left: 20px;
  display: flex;
  max-height: 28px;
  white-space: pre;
  text-overflow: ellipsis;
  overflow: hidden;
  border-radius: 4px;
}

#channels a .avatar {
  height: 20px;
  width: 20px;
  border-radius: 3px;
  margin-right: 10px;
  object-fit: contain;
}

#channels .notSelected:hover {
  background: hsla(120, 12.3%, 71.4%, 0.38); /*変更*/
}

#messages {
  flex-grow: 1;
}

#messages iframe {
  height: 100%;
  width: calc(100vw - 250px);
  border: none;
}
/*ここから付け足し*/
.topicSwitcher{margin: 2px;border:none;cursor:pointer;background: #E4E4E4}
.notSelected2:hover{background: hsla(120, 12.3%, 71.4%, 0.38);}
.selected {background: hsl(202, 56%, 91%); font-weight:600!important}
.selected2 {background: hsl(202, 56%, 91%);font-weight:600!important}
STYLE
