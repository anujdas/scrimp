# frozen_string_literal: true
# coding: UTF-8

require 'json'
require 'sinatra/base'

module Scrimp
  class App < Sinatra::Base
    set :static, true
    set :public_dir, File.expand_path('../public', __FILE__)
    set :views, File.expand_path('../views', __FILE__)
    set :haml, format: :html5

    PROTOCOLS = [Thrift::BinaryProtocol, Thrift::CompactProtocol, Thrift::JsonProtocol].freeze

    get '/' do
      haml :index
    end

    get '/services' do
      # for each detected service...
      responses = ThriftUtil.service_modules.each_with_object({}) do |service, service_h|
        # for each detected RPC...
        service_h[service] =
          ThriftUtil.service_rpcs(service).each_with_object({}) do |rpc, rpc_hash|
            # extract args and their types
            args_fields = ThriftUtil.service_args(service, rpc)::FIELDS.values
            args = args_fields.each_with_object({}) do |field, h|
              h[field[:name]] = ThriftUtil.type_info(field)
            end

            # extract returns/exceptions and their types
            result_fields = ThriftUtil.service_result(service, rpc)::FIELDS.values
            returns =
              if (success_field = result_fields.find { |f| f[:name] == 'success' })
                ThriftUtil.type_info(success_field)
              else
                { type: 'VOID' } # no success field == returns void
              end
            throws = result_fields.each_with_object({}) do |field, h|
              h[field[:name]] = ThriftUtil.type_info(field)
            end

            rpc_hash[rpc] = { args: args, returns: returns, throws: throws }
          end
      end

      content_type :json
      responses.to_json
    end

    get '/protocols' do
      content_type :json
      PROTOCOLS.each_with_object({}) { |p, h| h[p.name] = p.name }.to_json
    end

    get '/structs' do
      structs = ThriftUtil.all_structs.each_with_object({}) do |struct, h|
        h[struct] = struct::FIELDS.values.each_with_object({}) do |field, fields|
          fields[field[:name]] = ThriftUtil.type_info(field)
        end
      end

      content_type :json
      structs.to_json
    end

    post '/invoke' do
      invocation =
        if request.content_type == 'application/x-www-form-urlencoded' # yes it's lame
          JSON.parse(params['request-json'])
        else
          JSON.parse(request.body.read)
        end
      rpc = invocation['rpc']
      service_class = ThriftUtil.qualified_const(invocation['service'])
      args_class = ThriftUtil.service_args(service_class, rpc)
      result_class = ThriftUtil.service_result(service_class, rpc)

      # extract args in order (thanks, sorted hashes)
      args = args_class::FIELDS.values.map do |field|
        if (arg_val = invocation['args'][field[:name]])
          args_class.json_type_to_thrift_type(arg_val, field)
        end
      end

      response = {}
      begin
        socket = Thrift::Socket.new(invocation['host'], invocation['port'])
        transport = Thrift::FramedTransport.new(socket)
        protocol = ThriftUtil.qualified_const(invocation['protocol']).new(transport)
        client = service_class::Client.new(protocol)

        transport.open

        # make request
        result = client.public_send(invocation['rpc'], *args)
        # store result if successful (or null, if return type was 'void')
        response[:return] =
          if (success_field = result_class::FIELDS.values.find { |f| f[:name] == 'success' })
            ThriftUtil.thrift_type_to_json_type(result, success_field)
          end
      rescue Thrift::ApplicationException => e
        # a thrift exception (not a schema exception, but something else) occurred
        response[e.class.name] = {
          type: ThriftUtil.application_exception_type_string(e.type),
          message: e.message,
        }
      rescue => e
        raise e unless e.is_a?(Thrift::Struct_Union) # something unknown happened
        # save RPC-schema-defined exceptions
        response[e.class.name] = ThriftUtil.thrift_struct_to_json_map(e, e.class)
      ensure
        transport.close if transport
      end

      content_type :json
      response.to_json
    end
  end
end
