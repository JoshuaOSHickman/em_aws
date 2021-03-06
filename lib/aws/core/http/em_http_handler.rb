# http://docs.amazonwebservices.com/AWSRubySDK/latest/
require "em-synchrony"
require "em-synchrony/em-http"
require 'em-synchrony/thread'
module AWS
  
  module Core
    module Http
      
      # An EM-Synchrony implementation for Fiber based asynchronous ruby application.
      # See https://github.com/igrigorik/async-rails and 
      # http://www.mikeperham.com/2010/04/03/introducing-phat-an-asynchronous-rails-app/
      # for examples of Aync-Rails application
      # 
      # In Rails add the following to you various environment files:
      #
      # require 'aws-sdk'
      # require 'aws/core/http/em_http_handler'
      # AWS.config(
      # :http_handler => AWS::Http::EMHttpHandler.new(
      # :proxy => {:host => "http://myproxy.com",:port => 80}
      # )
      # )
      #
      class EMHttpHandler
        # @return [Hash] The default options to send to EM-Synchrony on each
        # request.
        attr_reader :default_request_options
             
        @@pools = {}
        def self.fetch_connection(url,pool_size)
          #@@pools[url] ||= 
          EventMachine::Synchrony::ConnectionPool.new(size: pool_size) do
            EM::HttpRequest.new(url)
          end
        end
        # Constructs a new HTTP handler using EM-Synchrony.
        #
        # @param [Hash] options Default options to send to EM-Synchrony on
        # each request. These options will be sent to +get+, +post+,
        # +head+, +put+, or +delete+ when a request is made. Note
        # that +:body+, +:head+, +:parser+, and +:ssl_ca_file+ are
        # ignored. If you need to set the CA file, you should use the
        # +:ssl_ca_file+ option to {AWS.config} or
        # {AWS::Configuration} instead.
        # Defaults pool_size to 5
        def initialize options = {}
          options[:pool_size] ||= 5
          #puts "Using EM-Synchrony for AWS requests"
          @default_request_options = options
        end
        
        def fetch_url(request)
          url = nil
          if request.use_ssl?
            url = "https://#{request.host}:443"
          else
            url = "http://#{request.host}"
          end
          url
        end
                   
        def fetch_headers(request)
          # Net::HTTP adds this header for us when the body is
          # provided, but it messes up signing
          headers = { 'content-type' => '' }
  
          # headers must have string values (net http calls .strip on them)
          request.headers.each_pair do |key,value|
            headers[key] = value.to_s
          end
  
          {:head => headers}
        end
        
        def fetch_proxy(request)
          opts={}
          if request.proxy_uri     
            opts[:proxy] = {:host => request.proxy_uri.host,:port => request.proxy_uri.port}
          end
          opts
        end
          
        def fetch_ssl(request)
          opts = {}
          if request.use_ssl? && request.ssl_verify_peer?
            opts[:private_key_file] = request.ssl_ca_file 
            opts[:cert_chain_file]= request.ssl_ca_file 
          end
          opts
        end
        
        def request_options(request)
          fetch_headers(request).
            merge(fetch_proxy(request)).
            merge(fetch_ssl(request))
        end
        
        def fetch_response(url,method,opts={})
          self.class.fetch_connection(url,@default_request_options[:pool_size]).execute(false) do |client|
            client.send(method, opts)   
          end
        end
    
        def handle(request,response)
          handle_it(request, response)
        end
                
        def handle_it(request, response)
          # get, post, put, delete, head
          method = request.http_method.downcase.to_sym
          raise "No Such Method" unless [:get, :post, :put, :delete, :head].member?(method)
          
          opts = request_options(request)# default_request_options.merge({
            #:path => request.uri, # might only be needed for S3, docs are unclear
          #}).merge(request_options(request))
          
          if (method == :get)
            opts[:query] = request.body
          else
            opts[:body] = request.body
          end
          
          url = fetch_url(request)
          
          begin
            http_response = fetch_response(url,method,opts)         
          rescue Timeout::Error, Errno::ETIMEDOUT => e
            response.timeout = true
            raise
          else
            response.body = http_response.response
            response.status = http_response.response_header.status.to_i
            response.headers = http_response.response_header.to_hash
          end
        end  
      end
    end
  end

  # We move this from AWS::Http to AWS::Core::Http, but we want the
  # previous default handler to remain accessible from its old namesapce
  # @private
  module Http
    EMHttpHandler = Core::Http::EMHttpHandler
  end
end