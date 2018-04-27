# frozen_string_literal: true
# coding: UTF-8

module Scrimp
  module ThriftUtil
    class << self
      # use a fully-qualified name to get a constant
      # no, it really doesn't belong here
      # but life will almost certainly go on
      def qualified_const(name)
        name.split('::').inject(Object) { |obj, name| obj.const_get(name) }
      end

      def application_exception_type_string(type)
        case type
        when Thrift::ApplicationException::UNKNOWN
          'UNKNOWN'
        when Thrift::ApplicationException::UNKNOWN_METHOD
          'UNKNOWN_METHOD'
        when Thrift::ApplicationException::INVALID_MESSAGE_TYPE
          'INVALID_MESSAGE_TYPE'
        when Thrift::ApplicationException::WRONG_METHOD_NAME
          'WRONG_METHOD_NAME'
        when Thrift::ApplicationException::BAD_SEQUENCE_ID
          'BAD_SEQUENCE_ID'
        when Thrift::ApplicationException::MISSING_RESULT
          'MISSING_RESULT'
        when Thrift::ApplicationException::INTERNAL_ERROR
          'INTERNAL_ERROR'
        when Thrift::ApplicationException::PROTOCOL_ERROR
          'PROTOCOL_ERROR'
        else
          type
        end
      end

      # For every Thrift service, the code generator produces a module. This
      # returns a list of all such modules currently loaded.
      def service_modules
        ObjectSpace.each_object(Module).
          select { |klass| klass != Thrift && klass < Thrift::Client }.
          map { |klass| qualified_const(klass.name.split('::')[0..-2].join('::')) }
      end

      # Given a service module (see service_modules above), returns a list of the names of all
      # the RPCs of that Thrift service.
      def service_rpcs(service_module)
        service_module::Client.instance_methods.
          select { |m| m =~ /^send_/ }.
          map { |m| m.to_s.sub('send_', '') }.
          select { |m| service_module.const_defined?("#{m.capitalize}_args") }
      end

      # Given a service module (see service_modules above) and a Thrift RPC name,
      # returns the class for the structure representing the RPC's arguments.
      def service_args(service_module, rpc_name)
        service_module.const_get("#{rpc_name.capitalize}_args")
      end

      # Given a service module (see service_modules above) and a Thrift RPC name,
      # returns the class for the structure representing the RPC's return value.
      def service_result(service_module, rpc_name)
        service_module.const_get("#{rpc_name.capitalize}_result")
      end

      # Returns a list of the classes for all Thrift structures that were loaded
      # at the time extend_structs was called (see below).
      def all_structs
        @@all_structs
      end

      # Finds all loaded Thrift struct classes, adds methods to them
      # for building them from hashes, and saves the list of them for
      # future reference.
      def extend_structs
        @@all_structs = ObjectSpace.each_object(Module).
          select { |klass| Thrift::Struct > klass || Thrift::Union > klass }
        @@all_structs.each { |klass| klass.extend(JsonThrift) }
      end

      # Converts a Thrift struct to a hash (suitable for conversion to json).
      def thrift_struct_to_json_map(struct, klass)
        klass::FIELDS.values.each_with_object({}) do |field, h|
          val = struct.public_send(field[:name])
          h[field[:name]] = thrift_type_to_json_type(val, field) if val
        end
      end

      # Converts a Thrift union to a hash (suitable for conversion to json).
      def thrift_union_to_json_map(union, klass)
        set_field = union.get_set_field.to_s
        field = klass::FIELDS.values.find { |f| f[:name] == set_field }

        { set_field => thrift_type_to_json_type(union.get_value, field) }
      end

      # Converts a Thrift value to a primitive, list, or hash (suitable for conversion to json).
      # The value is interpreted using a type info hash of the format returned by #type_info.
      def thrift_type_to_json_type(value, field)
        type = Thrift.type_name(field[:type])
        raise Thrift::TypeError.new("Type for #{field.inspect} not found.") unless type

        case type.sub('Types::', '')
        when 'STRUCT'
          if field[:class] < Thrift::Union
            thrift_union_to_json_map(value, field[:class])
          else
            thrift_struct_to_json_map(value, field[:class])
          end
        when 'LIST', 'SET'
          value.map { |e| thrift_type_to_json_type(e, field[:element]) }
        when 'MAP'
          value.map do |key, val|
            [thrift_type_to_json_type(key, field[:key]), thrift_type_to_json_type(val, field[:value])]
          end
        else
          (field[:enum_class] && field[:enum_class]::VALUE_MAP[value]) || value
        end
      end

      # Given a field description (as found in the FIELDS constant of a Thrift struct class),
      # returns a hash containing these elements:
      # - type - the name of the type, such as UNION, STRUCT, etc
      # - key (for maps) - the type info hash of the map's keys
      # - value (for maps) - the type info hash of the map's values
      # - element (for lists, sets) - the type info hash of the collection's elements
      # - enum (for enums) - a map of enum numeric value to name for the enum values
      def type_info(field)
        field = field.dup
        field[:type] = Thrift.type_name(field[:type]).sub('Types::', '')
        field.delete :name
        field[:key] = type_info(field[:key]) if field[:key]
        field[:value] = type_info(field[:value]) if field[:value]
        field[:element] = type_info(field[:element]) if field[:element]
        if enum = field[:enum_class]
          field[:enum] = enum.const_get 'VALUE_MAP'
        end
        field
      end
    end
  end
end

