# frozen_string_literal: true

require "fast/proxy_status"

describe Fast::ProxyStatus do
  # Section 2.3's table, the corpus's own data: name => recommended
  # status, response-only flag, extra parameters.
  def table
    {
      "dns_timeout" => [504, true, {}],
      "dns_error" => [502, true, { "rcode" => "String", "info-code" => "Integer" }],
      "destination_not_found" => [500, true, {}],
      "destination_unavailable" => [503, true, {}],
      "destination_ip_prohibited" => [502, true, {}],
      "destination_ip_unroutable" => [502, true, {}],
      "connection_refused" => [502, true, {}],
      "connection_terminated" => [502, false, {}],
      "connection_timeout" => [504, true, {}],
      "connection_read_timeout" => [504, false, {}],
      "connection_write_timeout" => [504, false, {}],
      "connection_limit_reached" => [503, true, {}],
      "tls_protocol_error" => [502, false, {}],
      "tls_certificate_error" => [502, true, {}],
      "tls_alert_received" => [502, false, { "alert-id" => "Integer", "alert-message" => "Token or String" }],
      "http_request_error" => ["The applicable 4xx status code", true,
                               { "status-code" => "Integer", "status-phrase" => "String" }],
      "http_request_denied" => [403, true, {}],
      "http_response_incomplete" => [502, false, {}],
      "http_response_header_section_size" => [502, false, { "header-section-size" => "Integer" }],
      "http_response_header_size" => [502, false, { "header-name" => "String", "header-size" => "Integer" }],
      "http_response_body_size" => [502, false, { "body-size" => "Integer" }],
      "http_response_trailer_section_size" => [502, false, { "trailer-section-size" => "Integer" }],
      "http_response_trailer_size" => [502, false, { "trailer-name" => "String", "trailer-size" => "Integer" }],
      "http_response_transfer_coding" => [502, false, { "coding" => "Token" }],
      "http_response_content_coding" => [502, false, { "coding" => "Token" }],
      "http_response_timeout" => [504, false, {}],
      "http_upgrade_failed" => [502, true, {}],
      "http_protocol_error" => [502, false, {}],
      "proxy_internal_response" => ["The most appropriate status code for the response", true, {}],
      "proxy_internal_error" => [500, true, {}],
      "proxy_configuration_error" => [500, true, {}],
      "proxy_loop_detected" => [502, true, {}]
    }
  end

  describe "ERRORS" do
    it "carries the 32 names of section 2.3 in document order" do
      expect(Fast::ProxyStatus::ERRORS.size).to be(:==, 32)
      expect(Fast::ProxyStatus::ERRORS.keys).to be(:==, table.keys)
    end

    it "carries every entry's three fields" do
      table.each do |name, (status, response_only, extra)|
        entry = Fast::ProxyStatus::ERRORS[name]
        expect(entry["recommended_status"]).to be(:==, status)
        expect(entry["response_only"]).to be(:==, response_only)
        expect(entry["extra_parameters"]).to be(:==, extra)
      end
    end

    it "is deep-frozen data" do
      expect(Fast::ProxyStatus::ERRORS.frozen?).to be(:==, true)
      Fast::ProxyStatus::ERRORS.each_value do |entry|
        expect(entry.frozen?).to be(:==, true)
        expect(entry["extra_parameters"].frozen?).to be(:==, true)
      end
    end

    it "carries the two prose recommended statuses verbatim" do
      expect(Fast::ProxyStatus::ERRORS["http_request_error"]["recommended_status"])
        .to be(:==, "The applicable 4xx status code")
      expect(Fast::ProxyStatus::ERRORS["proxy_internal_response"]["recommended_status"])
        .to be(:==, "The most appropriate status code for the response")
    end
  end

  describe "the registry lookups" do
    it "answers registered? with unknown passthrough" do
      expect(Fast::ProxyStatus.registered?("dns_timeout")).to be(:==, true)
      expect(Fast::ProxyStatus.registered?("proxy_loop_detected")).to be(:==, true)
      expect(Fast::ProxyStatus.registered?("vendor_error")).to be(:==, false)
    end

    it "answers recommended_status, nil for unknown" do
      expect(Fast::ProxyStatus.recommended_status("dns_timeout")).to be(:==, 504)
      expect(Fast::ProxyStatus.recommended_status("http_request_denied")).to be(:==, 403)
      expect(Fast::ProxyStatus.recommended_status("http_request_error"))
        .to be(:==, "The applicable 4xx status code")
      expect(Fast::ProxyStatus.recommended_status("vendor_error")).to be(:==, nil)
    end

    it "answers response_only?, false for unknown" do
      expect(Fast::ProxyStatus.response_only?("connection_timeout")).to be(:==, true)
      expect(Fast::ProxyStatus.response_only?("connection_read_timeout")).to be(:==, false)
      expect(Fast::ProxyStatus.response_only?("vendor_error")).to be(:==, false)
    end

    it "answers extra_parameters, nil for unknown" do
      expect(Fast::ProxyStatus.extra_parameters("dns_error"))
        .to be(:==, { "rcode" => "String", "info-code" => "Integer" })
      expect(Fast::ProxyStatus.extra_parameters("tls_alert_received"))
        .to be(:==, { "alert-id" => "Integer", "alert-message" => "Token or String" })
      expect(Fast::ProxyStatus.extra_parameters("proxy_internal_error")).to be(:==, {})
      expect(Fast::ProxyStatus.extra_parameters("vendor_error")).to be(:==, nil)
    end

    it "never gates a parse or an emit" do
      field = Fast::ProxyStatus.parse("ExampleCDN; error=vendor_error")
      expect(field.first.error).to be(:==, "vendor_error")
      expect(field.to_s).to be(:==, "ExampleCDN;error=vendor_error")
      expect(Fast::ProxyStatus.valid?("ExampleCDN; error=vendor_error")).to be(:==, true)
      strict = Fast::ProxyStatus.parse!("ExampleCDN; error=vendor_error")
      expect(strict.to_s).to be(:==, "ExampleCDN;error=vendor_error")
      hop = Fast::ProxyStatus::Hop.new(
        Fast::SFV::Token.new("x"),
        { "error" => Fast::SFV::Token.new("vendor_error") }
      )
      expect(hop.to_s).to be(:==, "x;error=vendor_error")
    end
  end

  describe "the error hierarchy" do
    it "is the family shape" do
      expect(Fast::ProxyStatus::Error < StandardError).to be(:==, true)
      expect(Fast::ProxyStatus::ParseError < Fast::ProxyStatus::Error).to be(:==, true)
      expect(Fast::ProxyStatus::SerializeError < Fast::ProxyStatus::Error).to be(:==, true)
      expect(Fast::ProxyStatus::ParseError.new("message", 7).offset).to be(:==, 7)
      expect(Fast::ProxyStatus::SerializeError.new("message", 0).offset).to be(:==, 0)
    end
  end
end
