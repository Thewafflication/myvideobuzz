
Function LoadYouTube() As Object
    ' global singleton
    return m.youtube
End Function

Function InitYouTube() As Object
    ' constructor
    this = CreateObject("roAssociativeArray")
    this.oauth_prefix = "https://www.google.com/accounts"
    this.link_prefix = "http://roku.toasterdesigns.net"
    this.devKey = "AI39si7xeR7W6rGgB9pZ3xBKHZnPVlBBdU3HZnhFXg8g7_3V8rplFNAT6rx_SVRzLRPhhNN-JARUjVg4JKGI5xjO00lK_Omb7g"
    this.protocol = "http"
    this.scope = this.protocol + "://gdata.youtube.com"
    this.prefix = this.scope + "/feeds/api"
    REM this.FieldsToInclude = "&fields=entry(title,author,link,gd:rating,media:group(media:category,media:description,media:thumbnail,yt:videoid))"
    
    this.CurrentPageTitle = ""
    this.screen=invalid
    this.video=invalid

    'API Calls
    this.ExecServerAPI = youtube_exec_api
    
    'Search
    this.SearchYouTube = youtube_search

    'History
    this.BrowseHistory = youtube_history

    'Featured
    this.BrowseFeatured = youtube_featured

    'Favorites
    this.BrowseFavorites = youtube_browse_favorites
    this.AddToFavorites = youtube_add_favorite
    this.RemoveFavorite = youtube_remove_favorite

    'User videos
    this.BrowseUserVideos = youtube_user_videos

	'related
	this.ShowRelatedVideos = youtube_related_videos

	'Play All
	this.PlayAllVideos = youtube_playall_videos

    'Videos
    this.DisplayVideoList = youtube_display_video_list
    this.FetchVideoList = youtube_fetch_video_list
    this.VideoDetails = youtube_display_video_springboard
    this.newVideoListFromXML = youtube_new_video_list
    this.newVideoFromXML = youtube_new_video
	this.ReturnVideoList = youtube_return_video

	'Categories
	this.CategoriesListFromXML  = youtube_new_video_cat_list

    this.UpdateButtons = update_buttons

    'Settings
    this.BrowseSettings = youtube_browse_settings
    this.DelinkPlayer = youtube_delink
    this.About = youtube_about 
	this.AddAccount = youtube_add_account
    
    'print "YouTube: init complete"
    return this
End Function


Function youtube_exec_api(request As Dynamic, username="default" As Dynamic) As Object
    'oa = Oauth()
    
    if username=invalid then
        username=""
    else
        username="users/"+username+"/"
    end if

    method = "GET"
    url_stub = request
    postdata = invalid
    headers = { }

    if type(request) = "roAssociativeArray" then
        if request.url_stub<>invalid then url_stub = request.url_stub
        if request.postdata<>invalid then : postdata = request.postdata : method="POST" : end if
        if request.headers<>invalid then headers = request.headers
        if request.method<>invalid then method = request.method
    end if
        
    if Instr(0, url_stub, "http://") OR Instr(0, url_stub, "https://") then
        http = NewHttp(url_stub)
    else
        http = NewHttp(m.prefix + "/" + username + url_stub)
    end if

    'if not headers.DoesExist("X-GData-Key") then headers.AddReplace("X-GData-Key", "key="+m.devKey)
    'if not headers.DoesExist("GData-Version") then headers.AddReplace("GData-Version", "2") 

    http.method = method
    http.AddParam("v","2","urlParams")
    'oa.sign(http,true)

    'print "----------------------------------"
	if Instr(1, request, "pkg:/") > 0 then 
		rsp = ReadAsciiFile(request)
	else if postdata<>invalid then
        rsp=http.PostFromStringWithTimeout(postdata, 10, headers)
        'print "postdata:",postdata
    else
        rsp=http.getToStringWithTimeout(10, headers)
    end if


    REM print "----------------------------------"
    REM print rsp
    REM print "----------------------------------"

    xml=ParseXML(rsp)

    returnObj = CreateObject("roAssociativeArray")
    returnObj.xml = xml
    returnObj.status = http.status
	if Instr(1, request, "pkg:/") < 0 then 
		returnObj.error = handleYoutubeError(returnObj)
	end if

    return returnObj
End Function

Function handleYoutubeError(rsp) As Dynamic
    ' Is there a status code? If not, return a connection error.
    if rsp.status=invalid then return ShowConnectionFailed()
    ' Don't check for errors if the response code was a 2xx or 3xx number
    if int(rsp.status/100)=2 or int(rsp.status/100)=3 return ""

    if not isxmlelement(rsp.xml) return ShowErrorDialog("API return invalid. Try again later", "Bad response")

    error=rsp.xml.GetNamedElements("error")[0]
    if error=invalid then
        ' we got an unformatted HTML response with the error in the title
        error=rsp.xml.GetChildElements()[0].GetChildElements()[0].GetText()
    else
        error=error.GetNamedElements("internalReason")[0].GetText()
    end if

    ShowDialog1Button("Error", error, "OK", true)
    return error
End Function










REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** Search
REM ********************************************************************
REM ********************************************************************
Sub youtube_search()
    port=CreateObject("roMessagePort") 
    screen=CreateObject("roSearchScreen")
    screen.SetMessagePort(port)
    
    history=CreateObject("roSearchHistory")
    screen.SetSearchTerms(history.GetAsArray())
    
    screen.Show()
    
    while true
        msg = wait(0, port)
        
        if type(msg) = "roSearchScreenEvent" then
            'print "Event: "; msg.GetType(); " msg: "; msg.GetMessage()
            if msg.isScreenClosed() then
                return
           else if msg.isPartialResult()
				screen.SetSearchTermHeaderText("Suggestions:")
				screen.SetClearButtonEnabled(false)
				screen.SetSearchTerms(GenerateSearchSuggestions(msg.GetMessage()))
            else if msg.isFullResult()
                keyword=msg.GetMessage()
                dialog=ShowPleaseWait("Please wait","Searching YouTube for "+Quote()+keyword+Quote())
                xml=m.ExecServerAPI("videos?q="+keyword,invalid)["xml"]
                if not isxmlelement(xml) then dialog.Close():ShowConnectionFailed():return
                videos=m.newVideoListFromXML(xml.entry)
                if videos.Count() > 0 then
                    history.Push(keyword)
                    screen.AddSearchTerm(keyword)
                    dialog.Close()
                    m.DisplayVideoList(videos, "Search Results for "+Chr(39)+keyword+Chr(39), xml.link, invalid)
                else
                    dialog.Close():ShowErrorDialog("No videos match your search","Search results")
                end if
            else if msg.isCleared() then
                history.Clear()
            end if
        end if
    end while
End Sub


Function GenerateSearchSuggestions(partSearchText As String) As Object
    suggestions = CreateObject("roArray", 1, true) 
    length = len(partSearchText)
	if length > 0 then
		searchRequest = CreateObject("roUrlTransfer")
		searchRequest.SetURL("http://suggestqueries.google.com/complete/search?hl=en&client=youtube&hjson=t&ds=yt&jsonp=window.yt.www.suggest.handleResponse&q=" + URLEncode(partSearchText))
		jsonAsString = searchRequest.GetToString() 
		jsonAsString = strReplace(jsonAsString,"window.yt.www.suggest.handleResponse(","")
        jsonAsString = Left(jsonAsString, Len(jsonAsString) -1)
		response = simpleJSONParser(jsonAsString) 

		if islist(response) = true
			if response.Count() > 1
				for each sugg in response[1]
						suggestions.Push(sugg[0])
				end for
			endif
		endif

    else
		history=CreateObject("roSearchHistory")
		suggestions = history.GetAsArray()
    endif 
    return suggestions
End Function

REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** Favorites
REM ********************************************************************
REM ********************************************************************
Sub youtube_browse_favorites()
    m.FetchVideoList("favorites", "Favorites", "default")
End Sub

Sub youtube_add_favorite(video As Object, buttons={} As Object)

    dialog=ShowPleaseWait("Adding to Favorites...", invalid)

    xml = CreateObject("roXMLElement")
    xml.SetName("entry")
    xml.AddAttribute("xmlns", "http://www.w3.org/2005/Atom")
    xml.AddElementWithBody("id", video.id)
    xml = xml.GenXML(true)

    request = CreateObject("roAssociativeArray")
    headers = CreateObject("roAssociativeArray")
    headers["Content-Type"] = "application/atom+xml"
    request.url_stub = "favorites"
    request.postdata = xml
    request.headers = headers

    response=m.ExecServerAPI(request, "default")
    
    dialog.Close()

    if tostr(response.error) = "" and int(response.status) = 201 then
        ShowDialog1Button("Added", "The video was added to your favorites.", "OK")
        m.video.EditLink=get_xml_edit_link(response.xml)
        m.UpdateButtons(buttons)
        m.screen.AddButton(3, "Remove from Favorites")
    else 
        ' this is a really awful way to handle 
        ' checking favorites and i should be ashamed
        if tostr(response.error) = "Video already in favorite list." then 
            do = ShowDialog2Buttons("Notice", "This video is already in your favorites. If you would like to remove it, visit the Favorites section from the main menu.", "OK", "Go To Favorites")
            if do = 1 then m.BrowseFavorites()
        end if
    end if

End Sub

Sub youtube_remove_favorite(video As Object, buttons={} As Object)

    dialog=ShowPleaseWait("Removing Favorite...", invalid)

    request = CreateObject("roAssociativeArray")
    request.url_stub = video.EditLink
    request.method = "DELETE"

    response=m.ExecServerAPI(request, "default")
    
    dialog.Close()

    if tostr(response.error) = "" and int(response.status) = 200 then
        ShowDialog1Button("Removed", "The video was removed from your favorites.", "OK")
        m.UpdateButtons(buttons)
        m.screen.AddButton(2, "Add to Favorites")
    end if


End Sub


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** History
REM ********************************************************************
REM ********************************************************************
Sub youtube_history()
    
End Sub


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** Featured
REM ********************************************************************
REM ********************************************************************
Sub youtube_featured()
    'm.FetchVideoList("standardfeeds/recently_featured", "Featured", invalid)
	m.FetchVideoList("users/vvarkala/playlists?v=2&max-results=50", "Featured", invalid, true)
End Sub


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** User uploads
REM ********************************************************************
REM ********************************************************************
Sub youtube_user_videos(username As String, userID As String)
    m.FetchVideoList("users/"+userID+"/uploads?orderby=published", "Videos By "+username, invalid)
End Sub


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** Related Videos
REM ********************************************************************
REM ********************************************************************
Sub youtube_related_videos(video As Object)
    m.FetchVideoList("videos/"+ video.id +"/related?v=2", "Related Videos", invalid)
	'GetYTBase("videos/" + showList[showIndex].ContentId + "/related?v=2&start-index=1&max-results=50"))
End Sub

REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** Play All Videos
REM ********************************************************************
REM ********************************************************************
Sub youtube_playall_videos(video As Object)
    m.FetchVideoList("users/"+userID+"/uploads?orderby=published", "Videos By "+username, invalid)
End Sub



REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** Poster/Video List Utils
REM ********************************************************************
REM ********************************************************************
Sub youtube_fetch_video_list(APIRequest As Dynamic, title As String, username As Dynamic,categories=false)
    
    REM fields = m.FieldsToInclude
    REM if Instr(0, APIRequest, "?") = 0 then
    REM     fields = "?"+Mid(fields, 2)
    REM end if

    screen=uitkPreShowPosterMenu("flat-episodic-16x9", title)
    screen.showMessage("Loading...")

    xml=m.ExecServerAPI(APIRequest, username)["xml"]
    if not isxmlelement(xml) then ShowConnectionFailed():return
    
	if categories = true then
		categories=m.CategoriesListFromXML(xml.entry)
		'PrintAny(0, "categoryList:", categories) 
		m.DisplayVideoList([], title, xml.link, screen, categories)
	else
		videos=m.newVideoListFromXML(xml.entry)
		m.DisplayVideoList(videos, title, xml.link, screen)
	end if
End Sub


Function youtube_return_video(APIRequest As Dynamic, title As String, username As Dynamic)
    xml=m.ExecServerAPI(APIRequest, username)["xml"]
    if not isxmlelement(xml) then 
		ShowConnectionFailed() 
		return []
	end if

	videos = m.newVideoListFromXML(xml.entry)
	metadata=GetVideoMetaData(videos)

	if xml.link<>invalid then
		for each link in xml.link
			if link@rel = "next" then 
				metadata.Push({shortDescriptionLine1: "More Results", action: "next", pageURL: link@href, HDPosterUrl:"pkg:/images/icon_next_episode.jpg", SDPosterUrl:"pkg:/images/icon_next_episode.jpg"})
			else if link@rel = "previous" then 
				metadata.Unshift({shortDescriptionLine1: "Back", action: "prev", pageURL: link@href, HDPosterUrl:"pkg:/images/icon_prev_episode.jpg", SDPosterUrl:"pkg:/images/icon_prev_episode.jpg"})
			end if
		end for
	end if

	return metadata
End Function

Sub youtube_display_video_list(videos As Object, title As String, links=invalid, screen=invalid, categories=invalid)
    if screen=invalid then
        screen=uitkPreShowPosterMenu("flat-episodic-16x9", title)
        screen.showMessage("Loading...")
    end if
    m.CurrentPageTitle = title

	'content_callback=[ff_data, m, function(ff_data, smugmug, cat_idx):return smugmug.getFFMetaData(ff_data[cat_idx]):end function]
	'onclick_callback=[ff_data, m, function(ff_data, smugmug, cat_idx, set_idx):smugmug.DisplayFriendsFamily(ff_data[cat_idx][set_idx]):end function]
    
	if categories<>invalid then
		categoryList = CreateObject("roArray", 100, true)
		for each category in categories
			categoryList.Push(category.title)
		next

        oncontent_callback = [categories, m, 
            function(categories, youtube, set_idx)
				'PrintAny(0, "category:", categories[set_idx]) 
                if youtube<>invalid then 
                    return youtube.ReturnVideoList(categories[set_idx].link, youtube.CurrentPageTitle, invalid)
				else
					return []
                end if
            end function]


        onclick_callback = [categories, m, 
            function(categories, youtube, video, category_idx, set_idx)
                if video[set_idx]["action"]<>invalid then 
                    return youtube.ReturnVideoList(video[set_idx]["pageURL"], youtube.CurrentPageTitle, invalid)
                else
                    youtube.VideoDetails(video[set_idx], youtube.CurrentPageTitle, video, set_idx)
					return video
                end if
            end function]

		uitkDoCategoryMenu(categoryList, screen, oncontent_callback, onclick_callback)
    else if videos.Count() > 0 then
        metadata=GetVideoMetaData(videos)

        for each link in links
            if link@rel = "next" then 
                metadata.Push({shortDescriptionLine1: "More Results", action: "next", pageURL: link@href, HDPosterUrl:"pkg:/images/icon_next_episode.jpg", SDPosterUrl:"pkg:/images/icon_next_episode.jpg"})
            else if link@rel = "previous" then 
                metadata.Unshift({shortDescriptionLine1: "Back", action: "prev", pageURL: link@href, HDPosterUrl:"pkg:/images/icon_prev_episode.jpg", SDPosterUrl:"pkg:/images/icon_prev_episode.jpg"})
            end if
        end for
        
        onselect = [1, metadata, m, 
            function(video, youtube, set_idx)
                if video[set_idx]["action"]<>invalid then 
                    youtube.FetchVideoList(video[set_idx]["pageURL"], youtube.CurrentPageTitle, invalid)
                else
                    youtube.VideoDetails(video[set_idx], youtube.CurrentPageTitle, video, set_idx)
                end if
            end function]
        uitkDoPosterMenu(metadata, screen, onselect)
    else
        uitkDoMessage("No videos found.", screen)
    end if
End Sub


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** working with metadata for the poster/springboard screens
REM ********************************************************************
REM ********************************************************************
Function youtube_new_video_cat_list(xmllist As Object) As Object
    'print "youtube_new_video_cat_list init"
    categoryList  = CreateObject("roList")
    for each record in xmllist
		''printAny(0, "xmllist:", record) 
		category  = CreateObject("roAssociativeArray")
        category.title = record.GetNamedElements("title")[0].GetText()
		category.link= validstr(record.content@src)

		if isnullorempty(category.link) then
			links = record.link
			for each link in links
				if Instr(1, link@rel, "user.uploads") > 0 then 
					category.link = validstr(link@href) + "&max-results=50"
				endif
			next
		end if

		categoryList.Push(category)
    next
    return categoryList
End Function



REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** working with metadata for the poster/springboard screens
REM ********************************************************************
REM ********************************************************************
Function youtube_new_video_list(xmllist As Object) As Object
    'print "youtube_new_video_list init"
    videolist=CreateObject("roList")
    for each record in xmllist
        video=m.newVideoFromXML(record)
        videolist.Push(video)
    next
    return videolist
End Function


Function youtube_new_video(xml As Object) As Object
    video = CreateObject("roAssociativeArray")
    video.youtube=m
    video.xml=xml
    video.GetID=function():return m.xml.GetNamedElements("media:group")[0].GetNamedElements("yt:videoid")[0].GetText():end function
    video.GetAuthor=get_xml_author
    video.GetUserID=function():return m.xml.GetNamedElements("media:group")[0].GetNamedElements("yt:uploaderId")[0].GetText():end function
    video.GetTitle=function():return m.xml.title[0].GetText():end function
    video.GetCategory=function():return m.xml.GetNamedElements("media:group")[0].GetNamedElements("media:category")[0].GetText():end function
    video.GetDesc=get_desc
    video.GetRating=get_xml_rating
    video.GetThumb=get_xml_thumb
    video.GetEditLink=get_xml_edit_link
    'video.GetLinks=function():return m.xml.GetNamedElements("link"):end function
    'video.GetURL=video_get_url
    return video
End Function


Function GetVideoMetaData(videos As Object)
    metadata=[]
        
    for each video in videos
        meta=CreateObject("roAssociativeArray")
        meta.ContentType="movie"
        
        meta.ID=video.GetID()
        meta.Author=video.GetAuthor()
        meta.Title=video.GetTitle()
        meta.Actors=meta.Author
        meta.Description=video.GetDesc()
        meta.Categories=video.GetCategory()
        meta.StarRating=video.GetRating()
        meta.ShortDescriptionLine1=meta.Title
        meta.SDPosterUrl=video.GetThumb()
        meta.HDPosterUrl=video.GetThumb()

        meta.xml=video.xml
        meta.UserID=video.GetUserID()
        meta.EditLink=video.GetEditLink(video.xml)

        meta.StreamFormat="mp4"
        meta.Streams=[]
        'meta.StreamBitrates=[]
        'meta.StreamQualities=[]
        'meta.StreamUrls=[]
        
        metadata.Push(meta)
    end for
    
    return metadata
End Function

Function get_desc() As Dynamic
    desc=m.xml.GetNamedElements("media:group")[0].GetNamedElements("media:description")
    if desc.Count()>0 then
		return Left(desc[0].GetText(), 300)
    end if
End Function

Function get_xml_author() As Dynamic
    credits=m.xml.GetNamedElements("media:group")[0].GetNamedElements("media:credit")
    if credits.Count()>0 then
        for each author in credits
            if author.GetAttributes()["role"] = "uploader" then return author.GetAttributes()["yt:display"]
        end for 
    end if
End Function

Function get_xml_rating() As Dynamic
    if m.xml.GetNamedElements("gd:rating").Count()>0 then
        return m.xml.GetNamedElements("gd:rating").GetAttributes()["average"].toInt()*20
    end if
    return invalid
End Function

Function get_xml_edit_link(xml) As Dynamic
    links=xml.GetNamedElements("link")
    if links.Count()>0 then
        for each link in links
            ''print link.GetAttributes()["rel"]
            if link.GetAttributes()["rel"] = "edit" then return link.GetAttributes()["href"]
        end for
    end if
    return invalid
End Function

Function get_xml_thumb() As Dynamic
    thumbs=m.xml.GetNamedElements("media:group")[0].GetNamedElements("media:thumbnail")
    if thumbs.Count()>0 then
        for each thumb in thumbs
            if thumb.GetAttributes()["yt:name"] = "mqdefault" then return thumb.GetAttributes()["url"]
        end for
        return m.xml.GetNamedElements("media:group")[0].GetNamedElements("media:thumbnail")[0].GetAttributes()["url"]
    end if
    return "pkg:/images/icon_s.jpg"
End Function


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** video details screen
REM ********************************************************************
REM ********************************************************************
Sub youtube_display_video_springboard(video As Object, breadcrumb As String, videos=invalid, idx=invalid)
    'print "Displaying video springboard"
    p = CreateObject("roMessagePort")
    screen = CreateObject("roSpringboardScreen")
    screen.SetMessagePort(p)
    m.screen=screen
    m.video=video
	''printAny(0, "videos:", videos)
    screen.SetDescriptionStyle("movie")
    screen.AllowNavLeft(true)
    screen.AllowNavRight(true)
    screen.SetPosterStyle("rounded-rect-16x9-generic")
    screen.SetDisplayMode("zoom-to-fill")
    screen.SetBreadcrumbText(breadcrumb, "Video")

    buttons = CreateObject("roAssociativeArray")

	buttons["play"] = screen.AddButton(0, "Play")
	buttons["play_all"] = screen.AddButton(1, "Play All")
	buttons["show_related"] = screen.AddButton(2, "Show Related Videos")
    buttons["more"] = screen.AddButton(3, "More Videos By "+ video.Author)

    if video.EditLink<>invalid then 
        'buttons["fav_rem"] = screen.AddButton(3, "Remove from Favorites")
    else
        'buttons["fav_add"] = screen.AddButton(2, "Add to Favorites")
    end if

    screen.SetContent(video)
    screen.Show()

    while true
        msg = wait(0, screen.GetMessagePort())
        if type(msg) = "roSpringboardScreenEvent" then
            if msg.isScreenClosed()
                'print "Closing springboard screen"
                exit while
            else if msg.isButtonPressed()
                'print "Button pressed: "; msg.GetIndex(); " " msg.GetData()
                if msg.GetIndex() = 0 then
                    DisplayVideo(video)
                else if msg.GetIndex() = 1 then
					for i=idx to videos.Count()-1  Step +1
						selectedVideo = videos[i]
						'print "Play ALL Index"
						'print i
					    'printAny(0, "Play All video:", selectedVideo)

						streamQualities = video_get_qualities(selectedVideo.id)
						if streamQualities<>invalid
							selectedVideo.Streams = streamQualities
							ret = DisplayVideo(selectedVideo)
							if(ret > 0) then
								Exit For
							endif
						end if
					end for
                else if msg.GetIndex() = 2 then
                    m.ShowRelatedVideos(video)
                else if msg.GetIndex() = 3 then
                    m.BrowseUserVideos(video.Author, video.UserID)
                else if msg.GetIndex() = 4 then
                    m.BrowseUserVideos(video.Author, video.UserID)
                else if msg.GetIndex() = 5 then
                    m.AddToFavorites(video, buttons)
                else if msg.GetIndex() = 6 then
                    m.RemoveFavorite(video, buttons)
                endif
            else
                'print "Unknown event: "; msg.GetType(); " msg: "; msg.GetMessage()
            endif
        end If
    end while
End Sub

Sub update_buttons(buttons)
    m.screen.ClearButtons()
    'print buttons
    if buttons["play"]<>invalid then m.screen.AddButton(0, "Play")
    if buttons["more"]<>invalid then m.screen.AddButton(1, "More Videos By "+m.video.Author)
End Sub


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** The video playback screen
REM ********************************************************************
REM ********************************************************************
Function DisplayVideo(content As Object)
    'print "Displaying video: "
    p = CreateObject("roMessagePort")
    video = CreateObject("roVideoScreen")
    video.setMessagePort(p)

	mp4VideoList = getVideoUrl(content.id, 0, "")
	''printAA(mp4VideoList)
	'printAny(0, "content:", content) 
	if mp4VideoList <> Invalid
		if not(isnullorempty(mp4VideoList.hdUrl))
			content.HDBranded = true
			content.IsHD = true
			content.FullHD = true
			content.Streams.Push({url: mp4VideoList.hdUrl, bitrate: 0, quality: true})
		elseif not(isnullorempty(mp4VideoList.hd1080pUrl))
			content.HDBranded = true
			content.IsHD = true
			content.FullHD = true
			content.Streams.Push({url: mp4VideoList.hd1080pUrl, bitrate: 0, quality: true})
		endif
		if not(isnullorempty(mp4VideoList.sdUrl))
			content.HDBranded = false
			content.IsHD = false
			content.FullHD = false
			content.Streams.Push({url: mp4VideoList.sdUrl, bitrate: 0, quality: false})
		endif
	else
		problem = ShowDialogNoButton("", "Having trouble finding YouTube's video formats map...")
		sleep(3000)
		problem.Close()
		return -1
	endif

    video.SetContent(content)
    video.show()
    ret = -1
    while true
        msg = wait(0, video.GetMessagePort())
        if type(msg) = "roVideoScreenEvent"
			if Instr(1, msg.getMessage(), "interrupted") > 0 then 
				ret = 1
			endif
            if msg.isScreenClosed() then 'ScreenClosed event
                'print "Closing video screen"
                video.Close()
                exit while
            else if msg.isRequestFailed()
                'print "play failed: "; msg.GetMessage()
            else
                'print "Unknown event: "; msg.GetType(); " msg: "; msg.GetMessage()
            end if
        end if
    end while
	return ret
End Function


REM ********************************************************************
REM ********************************************************************
REM ***** YouTube
REM ***** Get direct MP4 video URLs from YouTube's formats map
REM ********************************************************************
REM ********************************************************************
Function parseVideoFormatsMap(videoInfo As String) As Object
    
    REM print "-----------------------------------------------"
    REM print videoInfo
    REM print "-----------------------------------------------"

    r = CreateObject("roRegex", "(?:|&"+CHR(34)+")url_encoded_fmt_stream_map=([^(&|\$)]+)", "")
    videoFormatsMatches = r.Match(videoInfo)

    if videoFormatsMatches[0]<>invalid then
        videoFormats = videoFormatsMatches[1]
    else
        'print "parseVideoFormatsMap: didn't find any video formats"
        'print "---------------------------------------------------"
        'print videoInfo
        'print "---------------------------------------------------"
        return invalid
    end if

    sep1 = CreateObject("roRegex", "%2C", "")
    sep2 = CreateObject("roRegex", "%26", "")
    sep3 = CreateObject("roRegex", "%3D", "")

    videoURL = CreateObject("roAssociativeArray")
    videoFormatsGroup = sep1.Split(videoFormats)

    for each videoFormat in videoFormatsGroup
        videoFormatsElem = sep2.Split(videoFormat)
        videoFormatsPair = CreateObject("roAssociativeArray")
        for each elem in videoFormatsElem
            pair = sep3.Split(elem)
            if pair.Count() = 2 then
                videoFormatsPair[pair[0]] = pair[1]
            end if
        end for

        if videoFormatsPair["url"]<>invalid then 
            r1=CreateObject("roRegex", "\\\/", ""):r2=CreateObject("roRegex", "\\u0026", "")
            url=URLDecode(URLDecode(videoFormatsPair["url"]))
            r1.ReplaceAll(url, "/"):r2.ReplaceAll(url, "&")
        end if
        if videoFormatsPair["itag"]<>invalid then
            itag = videoFormatsPair["itag"]
        end if
        if videoFormatsPair["sig"]<>invalid then 
            sig = videoFormatsPair["sig"]
            url = url + "&signature=" + sig
        end if

        if Instr(0, LCase(url), "http") = 1 then 
            videoURL[itag] = url
        end if
    end for

    qualityOrder = ["18","22","37"]
    bitrates = [768,2250,3750]
    isHD = [false,true,true]
    streamQualities = []

    for i=0 to qualityOrder.Count()-1
        qn = qualityOrder[i]
        if videoURL[qn]<>invalid then
            streamQualities.Push({url: videoURL[qn], bitrate: bitrates[i], quality: isHD[i], contentid: qn})
        end if
    end for

    return streamQualities

End Function

function getVideoUrl (videoIdOrUrl as string, timeout = 0 as integer, loginCookie = "" as string) as object
   mp4VideoList = {sdUrl: "", hdUrl: "", hd1080pUrl: "", fallback1: "", fallback2: ""}
   if Left (LCase (videoIdOrUrl), 4) = "http"
      url = videoIdOrUrl
   else
      url = "http://www.youtube.com/get_video_info?hl=en&el=detailpage&video_id=" + videoIdOrUrl
   endif
   htmlString = ""
   port = CreateObject ("roMessagePort")
   ut = CreateObject ("roUrlTransfer")
   ut.SetPort (port)
   ut.AddHeader ("User-Agent", "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)")
   ut.AddHeader ("Cookie", loginCookie)
   ut.SetUrl (url)
   if ut.AsyncGetToString ()
      while true
         msg = Wait (timeout, port)
         if type (msg) = "roUrlEvent"
            status = msg.GetResponseCode ()
            if status = 200
               htmlString = msg.GetString ()
            endif
            exit while
         else if type (msg) = "Invalid"
            ut.AsyncCancel ()
            exit while
         endif
      end while
   endif
   urlEncodedFmtStreamMap = CreateObject ("roRegex", "url_encoded_fmt_stream_map=([^(" + Chr (34) + "|&|$)]*)", "").Match (htmlString)
   if urlEncodedFmtStreamMap.Count () > 1
      commaSplit = CreateObject ("roRegex", "%2C", "").Split (urlEncodedFmtStreamMap [1])
      for each commaItem in commaSplit
         pair = {itag: "", url: "", sig: ""}
         ampersandSplit = CreateObject ("roRegex", "%26", "").Split (commaItem)
         for each ampersandItem in ampersandSplit
            equalsSplit = CreateObject ("roRegex", "%3D", "").Split (ampersandItem)
            if equalsSplit.Count () = 2
               pair [equalsSplit [0]] = equalsSplit [1]
            endif
         end for
         if pair.url <> "" and Left (LCase (pair.url), 4) = "http"
            if pair.sig <> "" then signature = "&signature=" + pair.sig else signature = ""
            urlDecoded = ut.Unescape (ut.Unescape (pair.url + signature))
            if pair.itag = "18"
               mp4VideoList.sdUrl = urlDecoded
            else if pair.itag = "22"
               mp4VideoList.hdUrl = urlDecoded
            else if pair.itag = "37"
               mp4VideoList.hd1080pUrl = urlDecoded
            else if pair.itag = "36"
               mp4VideoList.fallback1 = urlDecoded
            else if pair.itag = "17"
               mp4VideoList.fallback2 = urlDecoded
            endif
         endif
      end for
   endif
   if mp4VideoList.sdUrl = "" and mp4VideoList.hdUrl = "" and mp4VideoList.hd1080pUrl = ""
	 if mp4VideoList.fallback1 <> ""
		mp4VideoList.sdUrl = mp4VideoList.fallback1
	 else if mp4VideoList.fallback2 <> ""
		mp4VideoList.sdUrl = mp4VideoList.fallback2
	 else
		mp4VideoList = Invalid
	  endif 
   endif
   return mp4VideoList
end function


function getMP4Url (videoIdOrUrl as string, timeout = 0 as integer, loginCookie = "" as string) as object
   mp4VideoList = {sdUrl: "", hdUrl: "", hd1080pUrl: "", fallback1: "", fallback2: ""}
   streamQualities = []
   if Left (LCase (videoIdOrUrl), 4) = "http"
      url = videoIdOrUrl
   else
      url = "http://www.youtube.com/get_video_info?hl=en&el=detailpage&video_id=" + videoIdOrUrl
   endif
   htmlString = ""
   port = CreateObject ("roMessagePort")
   ut = CreateObject ("roUrlTransfer")
   ut.SetPort (port)
   ut.AddHeader ("User-Agent", "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)")
   ut.AddHeader ("Cookie", loginCookie)
   ut.SetUrl (url)
   if ut.AsyncGetToString ()
      while true
         msg = Wait (timeout, port)
         if type (msg) = "roUrlEvent"
            status = msg.GetResponseCode ()
            if status = 200
               htmlString = msg.GetString ()
            endif
            exit while
         else if type (msg) = "Invalid"
            ut.AsyncCancel ()
            exit while
         endif
      end while
   endif
   urlEncodedFmtStreamMap = CreateObject ("roRegex", "url_encoded_fmt_stream_map=([^(" + Chr (34) + "|&|$)]*)", "").Match (htmlString)
   if urlEncodedFmtStreamMap.Count () > 1
      commaSplit = CreateObject ("roRegex", "%2C", "").Split (urlEncodedFmtStreamMap [1])
      for each commaItem in commaSplit
         pair = {itag: "", url: "", sig: ""}
         ampersandSplit = CreateObject ("roRegex", "%26", "").Split (commaItem)
         for each ampersandItem in ampersandSplit
            equalsSplit = CreateObject ("roRegex", "%3D", "").Split (ampersandItem)
            if equalsSplit.Count () = 2
               pair [equalsSplit [0]] = equalsSplit [1]
            endif
         end for
         if pair.url <> "" and Left (LCase (pair.url), 4) = "http"
            if pair.sig <> "" then signature = "&signature=" + pair.sig else signature = ""
            urlDecoded = ut.Unescape (ut.Unescape (pair.url + signature))
            if pair.itag = "18"
			   streamQualities.Push({url: urlDecoded, bitrate: 0, quality: false, contentid: pair.itag})
            else if pair.itag = "22"
				streamQualities.Push({url: urlDecoded, bitrate: 0, quality: true, contentid: pair.itag})
            else if pair.itag = "37"
               streamQualities.Push({url: urlDecoded, bitrate: 0, quality: true, contentid: pair.itag })
            else if pair.itag = "36"
               streamQualities.Push({url: urlDecoded, bitrate: 0, quality: false, contentid: pair.itag })
            else if pair.itag = "17"
               streamQualities.Push({url: urlDecoded, bitrate: 0, quality: false, contentid: pair.itag })
            endif
         endif
      end for
   endif

   return streamQualities
end function


Function video_get_qualities(videoID as String) As Object

    videoFormats = getMP4Url(videoID)
	if videoFormats.Count()>0 then
		hdvideo = []
         for each video in videoFormats
            if video.contentid = "22" then
               hdvideo.push(video)
            endif
         end for
		return videoFormats
    else
        'ShowErrorDialog("Having trouble finding YouTube's video formats map...")
		problem = ShowDialogNoButton("", "Having trouble finding YouTube's video formats map...")
		sleep(3000)
		problem.Close()
    end if
	return invalid


    'http = NewHttp("http://www.youtube.com/watch?v="+videoID)
    http = NewHttp("http://www.youtube.com/get_video_info?video_id="+videoID)
    rsp = http.getToStringWithTimeout(10)
    if rsp<>invalid then

        videoFormats = parseVideoFormatsMap(rsp)
        if videoFormats<>invalid then
            if videoFormats.Count()>0 then
                return videoFormats
            end if
        else
            'try again with full youtube page
            dialog=ShowPleaseWait("Looking for compatible videos...", invalid)
            http = NewHttp("http://www.youtube.com/watch?v="+videoID)
            rsp = http.getToStringWithTimeout(30)
            if rsp<>invalid then
                videoFormats = parseVideoFormatsMap(rsp)
                if videoFormats<>invalid then
                    if videoFormats.Count()>0 then
                        dialog.Close()
                        return videoFormats
                    end if
                else
                    dialog.Close()
                    ShowErrorDialog("Having trouble finding YouTube's video formats map...")
                end if
            end if
            dialog.Close()
        end if

    else
        ShowErrorDialog("HTTP Request for get_video_info failed!")
    end if
    
    return invalid
End Function