#!/bin/bash

QUERY_NUM=500 # number of getting messages per a request
eval `tail -n +2 zuliprc` # define $email, $site, $key
DOMAIN=`echo $site|sed -E 's/^.*(http|https):\/\/([^/]+).*/\2/g'`
mkdir -p $DOMAIN/{raw_json,html,data,avatars}

# Download messages
curl -sSX GET -G ${site}/api/v1/streams -u ${email}:$key | jq -r .streams[].name |fzf --height 50% --layout reverse -m | # Select streams to download
while read STREAM;do
  ANCHOR_COUNT=oldest
  LAST_MSG_ID=`curl -sSX GET -G ${site}/api/v1/messages -u ${email}:$key --data-urlencode anchor=newest  --data-urlencode num_before=1 --data-urlencode num_after=0 --data-urlencode include_anchor=true --data-urlencode narrow="[{\"operand\": \"$STREAM\", \"operator\": \"stream\"}]"|jq .messages[0].id `

  while :;do
      curl -sSX GET -G ${site}/api/v1/messages -u ${email}:$key --data-urlencode anchor=$ANCHOR_COUNT  --data-urlencode num_before=0 --data-urlencode num_after=$QUERY_NUM --data-urlencode include_anchor=true --data-urlencode apply_markdown=true --data-urlencode narrow="[{\"operand\": \"$STREAM\", \"operator\": \"stream\"}]" > $DOMAIN/raw_json/${STREAM}_$ANCHOR_COUNT.json
      ANCHOR_COUNT=$(( `cat $DOMAIN/raw_json/${STREAM}_$ANCHOR_COUNT.json|jq .messages[-1].id` + 1 ))
      (( $ANCHOR_COUNT > $LAST_MSG_ID )) && break
  done
done

# Convert json to html
ls $DOMAIN/raw_json |sed 's/_.*//g'|sort|uniq|
while read STREAM;do
test -e $DOMAIN/html/${STREAM}.html && continue # pass already downloaded streams
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

jq -s add $DOMAIN/raw_json/${STREAM}_*|sed 's/\\n//g' |jq -r '.messages|sort_by(.timestamp)[]|[.id, .sender_full_name, .content, .timestamp, .subject, .avatar_url]|@tsv'|
  awk -F "\t" '{print "<div class=\"message-gutter\" id=\""$1"\"><div class=\"\" data-stringify-ignore=\"true\"><img class=\"avatar\" src=\"avatars/avatar_img.png\" /></div><div class=\"\"><span class=\"sender\"><strong>["$5"]</strong>  "$2"</span><span class=\"timestamp\"><span class=\"c-timestamp__label\">"system("TZ=JST-9 date -d @"$4" +\"%Y/%b/%d %I:%M %p\"")"</span></span><br/><div class=\"text\">"$3"</div></div></div>"}' >>$DOMAIN/html/${STREAM}.html


# Download attachments
mkdir -p $DOMAIN/data/$STREAM
sed -E 's%.*(/user_uploads.*)\".*%\1%g' $DOMAIN/html/$STREAM.html|/bin/grep user_uploads|
while read URL;do
  FILE=`echo $URL|sed 's%.*/%%g'`
  curl -sSX GET $site`curl -sSX GET -G $site/api/v1$URL -u $email:$key|jq -r .url` -o $DOMAIN/data/$STREAM/$FILE
  sed -i "s%$URL%\.\./data/$STREAM/$FILE%g" $DOMAIN/html/$STREAM.html # link url
done


# FOOTER
cat <<FOOTTER >>$DOMAIN/html/${STREAM}.html
    </div>
    <script>
      if (window.location.hash) {
        document.getElementById(window.location.hash).scrollTo();
      } else {
        scrollBy({ top: 99999999 });
      }
    </script>
  </div>
</body>
</html>
FOOTTER
done


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

@font-face {
  font-family: "Lato";
  src: url('fonts/Lato-Regular.ttf') format('truetype');
  font-weight: normal;
  font-style: normal;
}

@font-face {
  font-family: "Lato";
  src: url('fonts/Lato-Bold.ttf') format('truetype');
  font-weight: bold;
  font-style: normal;
}

body, html {
  font-family: 'Lato', sans-serif;
  font-size: 14px;
  color: rgb(29, 28, 29);
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
  background: #c1c1c1;
}

.message-gutter {
  display: flex;
  margin: 10px;
  scroll-margin-top: 120px;
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
  background: #fff;
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

#index {
  display: flex;
  height: calc(100vh - 4px);
}

#channels {
  background: #39113E;
  width: 250px;
  color: #CDC3CE;
  padding-top: 10px;
  overflow: scroll;
  padding-bottom: 20px;
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
  color: #fff;
  margin-top: 10px;
}

#channels .section:first-of-type {
  margin-top: 0;
}

#channels a {
  padding: 5px;
  display: block;
  color: #CDC3CE;
  text-decoration: none;
  padding-left: 20px;
  display: flex;
  max-height: 28px;
  white-space: pre;
  text-overflow: ellipsis;
  overflow: hidden;
}

#channels a .avatar {
  height: 20px;
  width: 20px;
  border-radius: 3px;
  margin-right: 10px;
  object-fit: contain;
}

#channels a:hover {
  background: #301034;
  color: #edeced;
}

#messages {
  flex-grow: 1;
}

#messages iframe {
  height: 100%;
  width: calc(100vw - 250px);
  border: none;
}

#search {
  margin: 10px;
  text-align: center;
}

#search ul {
  list-style: none;
  display: flex;
  flex-direction: column;
  align-items: center;
}

#search li {
  padding: 5px;
  border-bottom: 1px solid #E2E2E2;
  background: hsl(0deg 0% 98%);
  border-radius: 5px;
  width: 600px;
  text-align: left;
  margin-bottom: 5px;
}

#search a {
  text-decoration: none;
  color: unset;
}
STYLE
