require "net/http"
require "uri"
require "tempfile"
require "json"

$aborted = false

def api_add(input_stream, file_name, json)
	uri = URI('http://192.168.0.152:42000/api/tasks/add/')
	request = Net::HTTP::Post.new(uri)
	boundary = "----RubyMultipartPost"
	request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
	post_body = []
	post_body << "--#{boundary}\r\n"
	unless input_stream.nil?
		post_body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{file_name}\"\r\n"
		post_body << "Content-Type: application/octet-stream\r\n\r\n"
		loop do
			byte = input_stream.read
			break if byte < 0
			post_body << [byte].pack('C*')
		end
		post_body << "\r\n--#{boundary}\r\n"
	end
	post_body << "Content-Disposition: form-data; name=\"json\"\r\n\r\n"
	post_body << "#{json}\r\n"
	post_body << "--#{boundary}--\r\n"
	request.body = post_body.join
	http = Net::HTTP.new(uri.host, uri.port)
	add_response = http.request(request)
	task_id = JSON.parse(add_response.body)["id"]
	return task_id
end

def api_wait_for_completion(task_id, progress)
	uri = URI("http://192.168.0.152:42000/api/tasks/status/#{task_id}")
	http = Net::HTTP.new(uri.host, uri.port)
	loop do
		if $aborted
			return
		end
		request = Net::HTTP::Get.new(uri)
		response = http.request(request)
		puts response.body
		json = JSON.parse(response.body)
		if json["status"] == "completed"
			return true
		end
		if json.has_key?("progress")
			progress.setSubProgress(json["progress"], 100)
		end
		sleep 3
	end
end

def api_get_result(task_id)
	uri = URI("http://192.168.0.152:42000/api/tasks/result/#{task_id}")
	http = Net::HTTP.new(uri.host, uri.port)
	request = Net::HTTP::Get.new(uri)
	response = http.request(request)
	result = JSON.parse(response.body)["result"]
	return result
end

def api_delete_task(task_id)
	uri = URI("http://192.168.0.152:42000/api/tasks/remove/#{task_id}")
	http = Net::HTTP.new(uri.host, uri.port)
	request = Net::HTTP::Delete.new(uri)
	response = http.request(request)
end

def transcribe_via_api(item, progress)
	progress.setSubStatusAndLogIt("Transcribing (Step 1/2)")
	input_stream = item.getBinary.getBinaryData.getInputStream
	transcribe_task_id = api_add(input_stream, item.getName, '{"type":"transcribe"}')
	complete = api_wait_for_completion(transcribe_task_id, progress)
	if $aborted
		return
	end
	transcribe_result = api_get_result(transcribe_task_id)
	api_delete_task(transcribe_task_id)
	return transcribe_result
end

def translate_via_api(source_language, texts, progress)
	progress.setSubStatusAndLogIt("Translating (Step 2/2)")
	data = JSON.generate({
		type: "translate",
		data: {
			sourcelanguage: source_language,
			targetlanguage: "de",
			texts: texts
		}
	})
	task_id = api_add(nil, nil, data)
	complete = api_wait_for_completion(task_id, progress)
	if $aborted
		return
	end
result = api_get_result(task_id)
	api_delete_task(task_id)
	return result
end

def process_item(item, progress)
	transcribe_result = transcribe_via_api(item, progress)
	if $aborted
		return
	end
	source_language = transcribe_result["language"]
	item.getCustomMetadata.putText("Audio Language", source_language)
	transcribe_texts = transcribe_result["texts"].map{ |e| e["text"] }
	joined_original_text = transcribe_texts.join(" ")
	progress.logMessage("Result: #{joined_original_text}")
	item.getCustomMetadata.putText("Audio Transcription", joined_original_text)
	translate_result = translate_via_api(source_language, transcribe_texts, progress)
	if $aborted
		return
	end
	translated_texts = translate_result["texts"].map{ |e| e["text"] }
	joined_translated_text = translated_texts.join(" ")
	progress.logMessage("Result: #{joined_translated_text}")
	item.getCustomMetadata.putText("Audio Translation", joined_translated_text)
end

# NX Bootstrap
begin
	require File.join(File.dirname(__FILE__), 'Nx.jar')
	java_import 'com.nuix.nx.NuixConnection'
	java_import 'com.nuix.nx.LookAndFeelHelper'
	java_import 'com.nuix.nx.dialogs.ProgressDialog'
	LookAndFeelHelper.setWindowsIfMetal
	NuixConnection.setUtilities($utilities)
	NuixConnection.setCurrentNuixVersion(NUIX_VERSION)
end

ProgressDialog.forBlock do |progress|
	progress.onAbort {
		$aborted = true
	}
	progress.setTitle("Audio transcription and translation")
	progress.setTimestampLoggedMessages(true)
	progress.setMainProgress(0, $current_selected_items.size)
	progress.setMainProgressVisible(true)
	progress.setSubProgressVisible(true)
	$current_selected_items.each_with_index do |item, index|
		if $aborted
			return
		end
		progress.setMainStatusAndLogIt("Processing item #{item.getName} (#{index+1} of #{$current_selected_items.size})")
		progress.setMainProgress(index, $current_selected_items.size)
		process_item(item, progress)
	end
	progress.setMainProgress(100, 100)
	progress.setSubProgress(100, 100)
	progress.setMainStatusAndLogIt("Done")
	progress.setSubStatus("")
	progress.setCompleted
end
