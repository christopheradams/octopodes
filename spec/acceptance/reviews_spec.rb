require 'spec_helper'
require 'rspec_api_documentation/dsl'

resource "Reviews" do
  header "Accept", :accept_header
  header "Content-Type", :content_type

  before (:all) do
  end

  after (:all) do
  end

  get "reviews" do
    let(:accept_header) { "application/vnd.collection+json" }

    example "Getting all reviews as Collection+JSON" do
      do_request

      expect(response_body).to have_json_path("collection")

      expect(status).to eq(200)
    end
  end

  bad_raw_posts = [
    '', '{}', '{"template":{}}', '{"template":{"data":[]}}',
    '{"template":{"data":[{"name": "n", "val": "v"}]}}',
    '{"template":{"data":[{"name": "whatever", "value": "wrong"}]}}'
  ]

  bad_raw_posts.each do |raw_post|

    post "reviews" do
      let(:accept_header) { "application/vnd.collection+json" }
      let(:content_type) { "application/vnd.collection+json" }

      let(:raw_post) { raw_post }

      example "Posting a review as Collection+JSON with bad input" do
        do_request

        expect(status).to eq(422)
      end
    end
  end

  post "reviews" do

      let(:accept_header) { "application/vnd.collection+json" }
      let(:content_type) { "application/vnd.collection+json" }

    let(:raw_post) { '{"template":{"data":[{"name": "name", "value": "Title"}, {"name": "url", "value": "http://example.org/web"}]}}' }

    example "Posting a review as Collection+JSON" do
      do_request

      puts response_body

      expect(response_headers).to include("Location")

      expect(status).to eq(201)
    end
  end

  get "reviews" do
    let(:accept_header) { "text/html" }

    example "Getting all reviews" do
      do_request

      expect(status).to eq(200)
    end
  end

  post "reviews" do
    let(:accept_header) { "text/html" }
    let(:content_type) { "application/x-www-form-urlencoded" }

    example "Posting a review as www-form with no data" do
      do_request

      expect(status).to eq(422)
    end
  end

  post "reviews" do
    parameter :name, "Title"
    parameter :url, "URL"

    let(:accept_header) { "text/html" }
    let(:content_type) { "application/x-www-form-urlencoded" }

    example "Posting a review as www-form" do
      do_request(:name => "The WebPage Title", :url => "http://example.org/web")

      expect(response_headers).to include("Location")

      expect(status).to eq(303)
    end
  end

end

resource "Review" do
  header "Accept", :accept_header
  header "Content-Type", :content_type

  before (:all) do
  end

  before (:all) do
  end

  get "/reviews/:id" do
    let(:accept_header) { "application/vnd.collection+json" }
    let(:id) { "webpage0" }

    example "Getting a review" do
      do_request

      expect(response_body).to have_json_path("collection")

      expect(status).to eq(200)
    end
  end

  get "reviews/:id" do
    let(:id) { "xxx" }

    example "Getting a non-existent item" do
      do_request

      expect(status).to eq(404)
    end
  end

end

