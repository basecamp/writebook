json.message "File uploaded successfully"
json.fileName @upload.filename.to_s
json.mimetype @upload.content_type
# main_app: rendered from inside the isolated ActionText namespace, where url helpers resolve against the engine
json.fileUrl main_app.action_text_markdown_upload_url(@upload.slug)
