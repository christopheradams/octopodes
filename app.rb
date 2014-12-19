require 'webmachine'
require 'webmachine/adapters/rack'
require 'json'
require 'collection-json'
require 'configatron'
require 'filemagic'

require_relative 'lib/records'
require_relative 'lib/templates'

I18n.config.enforce_available_locales = true

WebPages::connect(configatron.octopus.database)
Users::connect(configatron.octopus.database)

class OctopusResource < Webmachine::Resource
  include Webmachine::Resource::Authentication

  def is_authorized?(authorization_header)
    user_auth(authorization_header)
    true
  end

  private
  def user_auth(authorization_header)
    basic_auth(authorization_header, "Project Octopus") do |user, pass|
      @user = Users::check_auth(user, pass)
      !@user.empty?
    end
  end

  def menu
    base = @request.base_uri.to_s
    menu_items = [{:href => "#{base}reviews", :prompt => "Reviews"}]

    if @user.nil? || @user.empty?
      menu_items << {:href => "#{base}signups", :prompt => "Sign up"}
      menu_items << {:href => "#{base}login", :prompt => "Login"}
    else
      menu_items << {:href => "#{base}users/#{@user[:username]}", :prompt => @user[:username]}
    end

    menu_items
  end
end

class CollectionResource < OctopusResource
  def content_types_provided
    [["text/html", :to_html],
     ["application/vnd.collection+json", :to_cj]]
  end

  def content_types_accepted
    [["application/x-www-form-urlencoded", :from_urlencoded],
     ["application/vnd.collection+json", :from_cj]]
  end

  def base_uri
    @request.base_uri.to_s + '/'
  end

  def to_html
    CollectionTemplate.new(collection, title, menu, body).render
  end

  def to_cj
    collection.to_json
  end

  def trace?
    configatron.webmachine.trace
  end

  private
  def title
    "Reviewing the Use of Creative Works, One URL at a Time"
  end

  def body; end

  def collection
    CollectionJSON.generate_for(base_uri) do |builder|
      builder.set_version("1.0")
    end
  end

  def startkey
    @request.query["startkey"]
  end

  def prevkey
    @request.query["prevkey"]
  end

end

class HomeResource < CollectionResource
  def to_html
    PagesTemplate.new("home", title, menu).render
  end

  def collection
    reviews = WebPages::count
    users = Users::count
    CollectionJSON.generate_for(base_uri) do |builder|
      builder.set_version("1.0")
      builder.add_item(nil) do |item|
        item.add_data "webpageCount", prompt: "Web Pages Reviewed", value: reviews
        item.add_data "userCount", prompt: "Active Users", value: users
      end
    end
  end
end

class ReviewsResource < CollectionResource
  def allowed_methods
    ["GET", "POST"]
  end

  def is_authorized?(authorization_header)
    auth = user_auth(authorization_header)
    return true unless request.post?
    if auth != true
      @response.body = PagesTemplate.new("blank", "Please sign in", menu).render
    end
    auth
  end

  def base_uri
    @request.base_uri.to_s + 'reviews/'
  end

  def post_is_create?
    true
  end

  def create_path
    @create_path ||= WebPages::uuid
  end

  def from_cj
    begin
      cj_raw = '{"collection":' + request.body.to_s + '}'
      cj_doc = CollectionJSON.parse(cj_raw)

      if !cj_doc.template.nil? && !cj_doc.template.data.nil?
        rev = WebPages::create_from_collection(create_path, cj_doc, @user[:username])
        unless rev["error"].nil?
          @error = {"title" => rev["error"], "message" => rev["reason"]}
        end
      else
        @error = {"title" => "Bad Input", "message" => "Missing template data"}
      end
    rescue JSON::ParserError
      @error = {"title" => "Bad Input", "message" => "Malformed Collection+JSON"}
    end

    unless @error.nil?
      @response.body = to_cj
      @response.code = 422 # Unprocessable Entity
    end
  end

  def from_urlencoded
    begin
      data = URI::decode_www_form(request.body.to_s)
      rev = WebPages::create_from_form(create_path, data, @user[:username])

      if rev["ok"] === true
        # Clients (e.g., web browsers) submitting urlencoded data should
        # redirect to the newly created resource, since they won't act on
        # a 201 Created response.
        @response.do_redirect
      else
        @error = {"title" => rev["error"], "message" => rev["reason"]}
      end
    rescue ArgumentError
      @error = {"title" => "Bad Input", "message" => "Malformed WWW Form"}
    end

    unless @error.nil?
      @response.body = to_html
      @response.code = 422 # Unprocessable Entity
    end
  end

  private
  def title
    "Creative Works Re-used on the Web"
  end

  def collection
    documents.base_uri = base_uri
    documents.error = @error
    documents.include_template = false
    documents.include_queries = include_queries?
    documents.queries = @request.query
    documents.links = links
    documents.to_cj
  end

  def documents
    @documents ||= url.nil? ? WebPages::all(limit, startkey, prevkey) : WebPages::by_url(limit, url)
  end

  def links
    links = []

    unless @user.nil? || @user.empty?
      links << {:href => @request.base_uri.to_s + 'reviews;template',
                :rel => "template", :prompt => "Add a Work"}
    end

     links << {:href => @request.base_uri.to_s + 'reviews;queries',
               :rel => "queries", :prompt => "Search"}
  end

  def limit
    min, max, default = 1, 500, 10
    req = @request.query["limit"]
    (req =~ /^\d+$/) ? [min, [req.to_i, max].min].max : default
  end

  def url
    @request.query["url"]
  end

  def include_queries?
    request.path_info[:queries] === true
  end
end

class ReviewsTemplateResource < ReviewsResource

  def is_authorized?(authorization_header)
    auth = user_auth(authorization_header)
    if auth != true
      @response.body = PagesTemplate.new("blank", "Please sign in", menu).render
    end
    auth
  end

  private
  def body
    "Instructions: Fill in the form below with the URL and title of the work. You can optionally include a link to a media file on the page (like a JPG), plus the creator, license, and a description. If the work in question is a re-use of another work, fill in the 'Based on URL' field with a link to the original work."
  end

  def collection
    documents.base_uri = base_uri
    documents.error = @error
    documents.include_items = false
    documents.links = links
    documents.data = {"url" => url}
    documents.to_cj
  end

  def documents
    @documents ||= WebPageDocuments.new
  end
end

class ReviewResource < CollectionResource
  def allowed_methods
    ["GET"]
  end

  def base_uri
    @request.base_uri.to_s + 'reviews/'
  end

  def resource_exists?
    documents.count >= 1
  end

  private
  def id
    request.path_info[:id]
  end

  def title
    "Creative Work on the Web"
  end

  def collection
    documents.base_uri = base_uri
    documents.include_template = false
    documents.links = links
    documents.to_cj
  end

  def documents
    @documents ||= WebPages::find(id)
  end

  def links
    doc = documents.first
    url = doc["value"]["url"]

    add_work_uri = URI(@request.base_uri.to_s + "reviews;template")
    add_work_uri.query = URI.encode_www_form([["url", url]])

    unless @user.nil? || @user.empty?
      [{:href => add_work_uri.to_s, :rel => "template",
        :prompt => "Add another Work on this Page"}]
    else
      []
    end
  end

end

class SignupsResource < CollectionResource
  def allowed_methods
    ["GET", "POST"]
  end

  def base_uri
    @request.base_uri.to_s + 'signups/'
  end

  def post_is_create?
    true
  end

  def create_path
    @create_path ||= Users::uuid
  end

  def from_cj
    begin
      cj_raw = '{"collection":' + request.body.to_s + '}'
      cj_doc = CollectionJSON.parse(cj_raw)

      if !cj_doc.template.nil? && !cj_doc.template.data.nil?
        rev = Users::create_from_collection(create_path, cj_doc)
        unless rev["error"].nil?
          @error = {"title" => rev["error"], "message" => rev["reason"]}
        end
      else
        @error = {"title" => "Bad Input", "message" => "Missing template data"}
      end
    rescue JSON::ParserError
      @error = {"title" => "Bad Input", "message" => "Malformed Collection+JSON"}
    end

    unless @error.nil?
      @response.body = to_cj
      @response.code = 422 # Unprocessable Entity
    end
  end

  def from_urlencoded
    begin
      data = URI::decode_www_form(request.body.to_s)
      rev = Users::create_from_form(create_path, data)

      if rev["ok"] === true
        @response.do_redirect
      else
        @error = {"title" => rev["error"], "message" => rev["reason"]}
        @data = Datastore::trans_form_data(data)
      end
    rescue ArgumentError
      @error = {"title" => "Bad Input", "message" => "Malformed WWW Form"}
    end

    unless @error.nil?
      @response.body = to_html
      @response.code = 422 # Unprocessable Entity
    end
  end

  private
  def title
    "Sign up for Project Octopus"
  end

  def collection
    documents.base_uri = base_uri
    documents.error = @error
    documents.data = @data
    documents.to_cj
  end

  def documents
    @documents ||= SignupDocuments.new
  end

end

class SignupResource < CollectionResource

  def base_uri
    @request.base_uri.to_s + 'signups/'
  end

  def resource_exists?
    documents.count >= 1
  end

  private
  def identity
    request.path_info[:identity]
  end

  def title
    "Sign-up Submitted"
  end

  def collection
    documents.base_uri = base_uri
    documents.include_template = false
    documents.include_item_link = false
    documents.to_cj
  end

  def documents
    @documents ||= Users::identify(identity)
  end

end

class UsersResource < CollectionResource
  def allowed_methods
    ["GET"]
  end

  def base_uri
    @request.base_uri.to_s + 'users/'
  end

  private
  def collection
    documents.base_uri = base_uri
    documents.include_template = false
    documents.to_cj
  end

  def documents
    @documents ||= Users::usernames(10, startkey, prevkey)
  end

end

class UserResource < CollectionResource

  def base_uri
    @request.base_uri.to_s + 'users/'
  end

  def resource_exists?
    documents.count >= 1
  end

  private
  def title
    "#{username}"
  end

  def username
    request.path_info[:username]
  end

  def collection

    u = @user
    client_is_owner = !u.nil? && !u.empty? && u[:username] == username
    if client_is_owner
      documents.links = [{:href => base_uri + "#{username}/settings/",
                          :rel => "settings", :prompt => "Settings"}]
    end

    documents.base_uri = base_uri
    documents.include_template = false
    documents.to_cj
  end

  def documents
    @documents ||= Users::find(username)
  end

end

class IdentitiesResource < UserResource

  def allowed_methods
    ["GET", "POST"]
  end

  def content_types_provided
    [["text/html", :to_html]]
  end

  def content_types_accepted
    [["application/x-www-form-urlencoded", :from_urlencoded]]
  end

  def base_uri
    @request.base_uri.to_s + "users/#{username}/settings/"
  end

  def post_is_create?
    true
  end

  def create_path
    @create_path ||= Users::uuid
  end

  def is_authorized?(authorization_header)
    auth = user_auth(authorization_header)
    if auth != true
      @response.body = PagesTemplate.new("blank", "Please sign in", menu).render
    end
    auth
  end

  def forbidden?
    forbidden = @user.nil? || @user.empty? || @user[:username] != username
    if forbidden
      @response.body = PagesTemplate.new("blank", "Forbidden", menu).render
    end
    forbidden
  end

  def from_urlencoded
    begin
      data = URI::decode_www_form(request.body.to_s)
      rev = Users::save_from_form(create_path, username, data)

      if rev["ok"] === true
        @response.do_redirect
      else
          @error = {"title" => rev["error"], "message" => rev["reason"]}
      end
    rescue ArgumentError
      @error = {"title" => "Bad Input", "message" => "Malformed WWW Form"}
    end

    unless @error.nil?
      @response.body = to_html
      @response.code = 422 # Unprocessable Entity
    end
  end

  private
  def title
    "Change Your Password"
  end

  def collection
    documents.links = [{:href => base_uri, :rel => "settings",
                        :prompt => "Settings"}]
    documents.base_uri = base_uri
    documents.error = @error
    documents.include_template = true
    documents.include_items = false
    documents.to_cj
  end

end

class IdentityResource < CollectionResource

  def content_types_provided
    [["text/html", :to_html]]
  end

  def is_authorized?(authorization_header)
    true
  end

  def resource_exists?
    true
  end

  private
  def title
    "Please login again"
  end

end

class FeedResource < Webmachine::Resource
  def content_types_provided
    [["application/atom+xml", :to_atom]]
  end

  def base_uri
    @request.base_uri.to_s + 'u/'
  end

  def to_atom
    documents.base_uri = base_uri
    documents.to_atom.to_s
  end

  private
  def documents
    @documents ||= WebPages::all(limit)
  end

  def limit
    20
  end
end

class FeedItemResource < Webmachine::Resource
  def allowed_methods
    ["GET"]
  end

  def resource_exists?
    false
  end

  def previously_existed?
    documents.count >= 1
  end

  def moved_temporarily?
    request.base_uri.to_s + 'reviews/' + id
  end

  def trace?
    configatron.webmachine.trace
  end

  private
  def id
    request.path_info[:id]
  end

  def documents
    @documents ||= WebPages::find(id)
  end
end

class AssetsResource < Webmachine::Resource
  def allowed_methods
    ["HEAD", "GET"]
  end

  def content_types_provided
    [["*/*", :to_file]]
  end

  def resource_exists?
    File.expand_path(file_path).start_with?(base_path) and File.file?(file_path)
  end

  def last_modified
    File.mtime(file_path)
  end

  def to_file
    response.headers["Content-Type"] = mime_type
    File.open(file_path, "r")
  end

  private
  def base_path
    File.expand_path("public")
  end

  def file_path
    File.join(base_path, filename)
  end

  def filename
    request.disp_path
  end

  def mime_type
    case File.extname(file_path)
    when '.css'
      'text/css'
    when '.js'
      'application/javascript'
    else
      FileMagic.new(FileMagic::MAGIC_MIME).file(file_path)
    end
  end
end

class FaviconResource < AssetsResource
  def content_types_provided
    [["image/x-icon", :to_file]]
  end

  private
  def base_path
    File.expand_path("public")
  end

  def filename
    "favicon.ico"
  end
end

class LoginResource < CollectionResource
  def content_types_provided
    [["text/html", :to_html]]
  end

  def is_authorized?(authorization_header)
    @response.body = CollectionTemplate.new(collection, "Please try again or sign up for an account", menu).render
    user_auth(authorization_header)
  end

  private
  def title
    "Thank you for logging in"
  end

end

class AboutResource < OctopusResource
  def allowed_methods
    ["GET"]
  end

  def content_types_provided
    [["text/html", :to_html]]
  end

  def to_html
    PagesTemplate.new("about", "About", menu).render
  end
end

class PaperResource < OctopusResource
  def allowed_methods
    ["GET"]
  end

  def content_types_provided
    [["text/html", :to_html]]
  end

  def to_html
    PagesTemplate.new("blank", "Read the Paper - Coming Soon", menu).render
  end
end

App = Webmachine::Application.new do |app|
  app.configure do |config|
    config.adapter = :Rack
  end
  app.routes do
    add [], HomeResource
    add ["favicon.ico"], FaviconResource
    add ["assets", '*'], AssetsResource
    add ["docs", '*'], AssetsResource

    add ["reviews"], ReviewsResource
    add ["reviews;template"], ReviewsTemplateResource
    add ["reviews;queries"], ReviewsResource, :queries => true
    add ["reviews", :id], ReviewResource

    add ["signups"], SignupsResource
    add ["signups", :identity], SignupResource
    add ["users"], UsersResource
    add ["users", :username], UserResource
    add ["users", :username, "settings"], IdentitiesResource
    add ["users", :username, "settings", :setting], IdentityResource
    add ["login"], LoginResource

    add ["feed"], FeedResource
    add ["u", :id], FeedItemResource

    add ["about"], AboutResource
    add ["paper"], PaperResource

    if configatron.webmachine.trace
      add ['trace', '*'], Webmachine::Trace::TraceResource
    end
  end
end
