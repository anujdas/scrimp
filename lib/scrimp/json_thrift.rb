require 'set'

module Scrimp
  # Generated Thrift struct classes can extend this module to gain a #from_hash method that will build
  # them from a hash representation. The hash representation uses only types that can be readily converted to/from json.
  # See the README's "JSON Representation" section.
  module JsonThrift
    # Construct a new instance of the class extending this module and populate its fields with values from a hash.
    #
    # @param [Hash] hash populates fields of the Thrift struct that have names that match its keys (string keys only)
    # @return [Thrift::Struct]
    # @raise [Thrift::TypeError] if one of the values in +hash+ is not a valid type for its field or a field exists with
    #                            an invalid type
    def from_hash(hash)
      new.tap do |struct|
        hash.each_pair do |k, v|
          field = struct.struct_fields.values.find { |f| f[:name] == k }
          value = json_type_to_thrift_type(v, field)
          Thrift.check_type(value, field, field[:name])
          struct.send("#{field[:name]}=", value)
        end
      end
    end

    # Converts +value+ to a Thrift type that can be passed to a Thrift setter for the given +field+.
    #
    # @param value [Object] the parsed json type to be converted
    # @param field [Hash] the Thrift field that will accept +value+
    # @return [Object] +value+ converted to a type that the setter for +field+ will expect
    # @raise [Thrift::TypeError] if +field+ has an invalid type
    def json_type_to_thrift_type(value, field)
      type = Thrift.type_name(field[:type])
      raise Thrift::TypeError.new("Type for #{field.inspect} not found.") unless type

      case type.sub('Types::', '')
      when 'STRUCT'
        field[:class].from_hash(value)
      when 'MAP'
        # JSON doesn't allow arbitrary keys, so maps are sent as [k, v] pairs
        value.each_with_object({}) do |(k, v), h|
          thrift_k = json_type_to_thrift_type(k, field[:key])
          thrift_v = json_type_to_thrift_type(v, field[:value])
          h[thrift_k] = thrift_v
        end
      when 'LIST'
        value.map { |e| json_type_to_thrift_type(e, field[:element]) }
      when 'SET'
        value.map { |e| json_type_to_thrift_type(e, field[:element]) }.to_set
      when 'DOUBLE'
        value.to_f
      when 'VOID'
        nil
      else # TODO: STOP
        (field[:enum_class] && field[:enum_class]::VALUE_MAP.key(value)) || value
      end
    end
  end
end
