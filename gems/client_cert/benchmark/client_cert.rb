# frozen_string_literal: true

# The fast-client-cert benchmark: the 19 paths whose allocation
# budgets test/fast/client_cert/allocations.rb freezes — the six
# Cert paths, the nine Chain paths and the four PEM-surgery paths —
# each on that test's own input (the RFC 9440 Appendix A vectors:
# the Figure 2 Client-Cert value, the Figure 3 Client-Cert-Chain
# value with its split-line form, and the three Figure 1 PEM
# blocks). One row per budget test, the same inputs, so the
# objects/call column and the frozen budgets are one discipline.
# Both runtime modes run: the plain interpreter (the no-JIT floor)
# and YJIT (the compiling runtime, the common production
# configuration); the ruby banner records which ran. benchmark-ips;
# quick mode with BENCH_QUICK=1.
#
# There is no comparator row: no other Ruby implementation of RFC
# 9440 exists — starry, the fast-http-fields family's reference
# comparator for fast-sfv, implements the Structured Fields
# substrate, not these fields. The numbers hold fast-client-cert to
# its own budgets: the objects/call column matches the frozen budget
# inputs, and it is the column the tests catch; i/s is indicative,
# never contractual.
#
#   bundle exec ruby benchmark/client_cert.rb
#   BENCH_QUICK=1 bundle exec ruby benchmark/client_cert.rb
#   bundle exec ruby --yjit benchmark/client_cert.rb
#
# Run from the repo root via the gem's own bundle
# (gems/client_cert/gems.rb):
#
#   BENCH_QUICK=1 BUNDLE_GEMFILE=gems/client_cert/gems.rb bundle \
#     exec ruby gems/client_cert/benchmark/client_cert.rb
#   BUNDLE_GEMFILE=gems/client_cert/gems.rb bundle exec ruby --yjit \
#     gems/client_cert/benchmark/client_cert.rb

require "benchmark/ips"
require_relative "../lib/fast/client_cert"

# the Appendix A Figure 2 value (the end-entity certificate).
FIG2 = ":MIIBqDCCAU6gAwIBAgIBBzAKBggqhkjOPQQDAjA6MRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWN" \
       "hdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF0ZSBDQTAeFw0yMDAxMTQyMjU1MzNaFw0yMTAxMjM" \
       "yMjU1MzNaMA0xCzAJBgNVBAMMAkJDMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE8YnXXfaUgmn" \
       "MtOXU/IncWalRhebrXmckC8vdgJ1p5Be5F/3YC8OthxM4+k1M6aEAEFcGzkJiNy6J84y7uzo9M6N" \
       "yMHAwCQYDVR0TBAIwADAfBgNVHSMEGDAWgBRm3WjLa38lbEYCuiCPct0ZaSED2DAOBgNVHQ8BAf8" \
       "EBAMCBsAwEwYDVR0lBAwwCgYIKwYBBQUHAwIwHQYDVR0RAQH/BBMwEYEPYmRjQGV4YW1wbGUuY29" \
       "tMAoGCCqGSM49BAMCA0gAMEUCIBHda/r1vaL6G3VliL4/Di6YK0Q6bMjeSkC3dFCOOB8TAiEAx/k" \
       "HSB4urmiZ0NX5r5XarmPk0wmuydBVoU4hBVZ1yhk=:"
# the Appendix A Figure 3 value (the two-member chain).
FIG3 = ":MIIB5jCCAYugAwIBAgIBFjAKBggqhkjOPQQDAjBWMQswCQYDVQQGEwJVUzEbMBkGA1UECgwSTGV" \
       "0J3MgQXV0aGVudGljYXRlMSowKAYDVQQDDCFMZXQncyBBdXRoZW50aWNhdGUgUm9vdCBBdXRob3J" \
       "pdHkwHhcNMjAwMTE0MjEzMjMwWhcNMzAwMTExMjEzMjMwWjA6MRswGQYDVQQKDBJMZXQncyBBdXR" \
       "oZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM4" \
       "9AwEHA0IABJf+aA54RC5pyLAR5yfXVYmNpgd+CGUTDp2KOGhc0gK91zxhHesEYkdXkpS2UN8Kati" \
       "+yHtWCV3kkhCngGyv7RqjZjBkMB0GA1UdDgQWBBRm3WjLa38lbEYCuiCPct0ZaSED2DAfBgNVHSM" \
       "EGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQ" \
       "EAwIBhjAKBggqhkjOPQQDAgNJADBGAiEA5pLvaFwRRkxomIAtDIwg9D7gC1xzxBl4r28EzmSO1pc" \
       "CIQCJUShpSXO9HDIQMUgH69fNDEMHXD3RRX5gP7kuu2KGMg==:, :MIICBjCCAaygAwIBAgIJAKS" \
       "0yiqKtlhoMAoGCCqGSM49BAMCMFYxCzAJBgNVBAYTAlVTMRswGQYDVQQKDBJMZXQncyBBdXRoZW5" \
       "0aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBSb290IEF1dGhvcml0eTAeFw0yMDA" \
       "xMTQyMTI1NDVaFw00MDAxMDkyMTI1NDVaMFYxCzAJBgNVBAYTAlVTMRswGQYDVQQKDBJMZXQncyB" \
       "BdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBSb290IEF1dGhvcml0eTB" \
       "ZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFoaHU+Z5bPKmGzlYXtCf+E6HYj62fORaHDOrt+yyh3" \
       "H/rTcs7ynFfGn+gyFsrSP3Ez88rajv+U2NfD0o0uZ4PmjYzBhMB0GA1UdDgQWBBTEA2Q6eecKu9g" \
       "9yb5glbkhhVINGDAfBgNVHSMEGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDAPBgNVHRMBAf8EBTA" \
       "DAQH/MA4GA1UdDwEB/wQEAwIBhjAKBggqhkjOPQQDAgNIADBFAiEAmAeg1ycKHriqHnaD4M/UDBp" \
       "QRpkmdcRFYGMg1Qyrkx4CIB4ivz3wQcQkGhcsUZ1SOImd/lq1Q0FLf09rGfLQPWDc:"
# Figure 3, first member — the intermediate CA.
FIG3_MEMBER1 = ":MIIB5jCCAYugAwIBAgIBFjAKBggqhkjOPQQDAjBWMQswCQYDVQQGEwJVUzEbMBkGA1UECgwSTGV" \
               "0J3MgQXV0aGVudGljYXRlMSowKAYDVQQDDCFMZXQncyBBdXRoZW50aWNhdGUgUm9vdCBBdXRob3J" \
               "pdHkwHhcNMjAwMTE0MjEzMjMwWhcNMzAwMTExMjEzMjMwWjA6MRswGQYDVQQKDBJMZXQncyBBdXR" \
               "oZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM4" \
               "9AwEHA0IABJf+aA54RC5pyLAR5yfXVYmNpgd+CGUTDp2KOGhc0gK91zxhHesEYkdXkpS2UN8Kati" \
               "+yHtWCV3kkhCngGyv7RqjZjBkMB0GA1UdDgQWBBRm3WjLa38lbEYCuiCPct0ZaSED2DAfBgNVHSM" \
               "EGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQ" \
               "EAwIBhjAKBggqhkjOPQQDAgNJADBGAiEA5pLvaFwRRkxomIAtDIwg9D7gC1xzxBl4r28EzmSO1pc" \
               "CIQCJUShpSXO9HDIQMUgH69fNDEMHXD3RRX5gP7kuu2KGMg==:"
# Figure 3, second member — the root CA.
FIG3_MEMBER2 = ":MIICBjCCAaygAwIBAgIJAKS0yiqKtlhoMAoGCCqGSM49BAMCMFYxCzAJBgNVBAYTAlVTMRswGQY" \
               "DVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBSb29" \
               "0IEF1dGhvcml0eTAeFw0yMDAxMTQyMTI1NDVaFw00MDAxMDkyMTI1NDVaMFYxCzAJBgNVBAYTAlV" \
               "TMRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F" \
               "0ZSBSb290IEF1dGhvcml0eTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFoaHU+Z5bPKmGzlYXt" \
               "Cf+E6HYj62fORaHDOrt+yyh3H/rTcs7ynFfGn+gyFsrSP3Ez88rajv+U2NfD0o0uZ4PmjYzBhMB0" \
               "GA1UdDgQWBBTEA2Q6eecKu9g9yb5glbkhhVINGDAfBgNVHSMEGDAWgBTEA2Q6eecKu9g9yb5glbk" \
               "hhVINGDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAKBggqhkjOPQQDAgNIADBFAiE" \
               "AmAeg1ycKHriqHnaD4M/UDBpQRpkmdcRFYGMg1Qyrkx4CIB4ivz3wQcQkGhcsUZ1SOImd/lq1Q0F" \
               "Lf09rGfLQPWDc:"
# Figure 1, first block — the end-entity certificate (the PEM form of FIG2).
# Figure 1, first block — the end-entity certificate (the PEM form of FIG2).
BLOCK1 = <<~PEM
  -----BEGIN CERTIFICATE-----
  MIIBqDCCAU6gAwIBAgIBBzAKBggqhkjOPQQDAjA6MRswGQYDVQQKDBJMZXQncyBB
  dXRoZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF0ZSBDQTAeFw0yMDAx
  MTQyMjU1MzNaFw0yMTAxMjMyMjU1MzNaMA0xCzAJBgNVBAMMAkJDMFkwEwYHKoZI
  zj0CAQYIKoZIzj0DAQcDQgAE8YnXXfaUgmnMtOXU/IncWalRhebrXmckC8vdgJ1p
  5Be5F/3YC8OthxM4+k1M6aEAEFcGzkJiNy6J84y7uzo9M6NyMHAwCQYDVR0TBAIw
  ADAfBgNVHSMEGDAWgBRm3WjLa38lbEYCuiCPct0ZaSED2DAOBgNVHQ8BAf8EBAMC
  BsAwEwYDVR0lBAwwCgYIKwYBBQUHAwIwHQYDVR0RAQH/BBMwEYEPYmRjQGV4YW1w
  bGUuY29tMAoGCCqGSM49BAMCA0gAMEUCIBHda/r1vaL6G3VliL4/Di6YK0Q6bMje
  SkC3dFCOOB8TAiEAx/kHSB4urmiZ0NX5r5XarmPk0wmuydBVoU4hBVZ1yhk=
  -----END CERTIFICATE-----
PEM
# Figure 1, second block — the intermediate CA (the PEM form of FIG3_MEMBER1).
# Figure 1, second block — the intermediate CA (the PEM form of FIG3_MEMBER1).
BLOCK2 = <<~PEM
  -----BEGIN CERTIFICATE-----
  MIIB5jCCAYugAwIBAgIBFjAKBggqhkjOPQQDAjBWMQswCQYDVQQGEwJVUzEbMBkG
  A1UECgwSTGV0J3MgQXV0aGVudGljYXRlMSowKAYDVQQDDCFMZXQncyBBdXRoZW50
  aWNhdGUgUm9vdCBBdXRob3JpdHkwHhcNMjAwMTE0MjEzMjMwWhcNMzAwMTExMjEz
  MjMwWjA6MRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxGzAZBgNVBAMMEkxB
  IEludGVybWVkaWF0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJf+aA54
  RC5pyLAR5yfXVYmNpgd+CGUTDp2KOGhc0gK91zxhHesEYkdXkpS2UN8Kati+yHtW
  CV3kkhCngGyv7RqjZjBkMB0GA1UdDgQWBBRm3WjLa38lbEYCuiCPct0ZaSED2DAf
  BgNVHSMEGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDASBgNVHRMBAf8ECDAGAQH/
  AgEAMA4GA1UdDwEB/wQEAwIBhjAKBggqhkjOPQQDAgNJADBGAiEA5pLvaFwRRkxo
  mIAtDIwg9D7gC1xzxBl4r28EzmSO1pcCIQCJUShpSXO9HDIQMUgH69fNDEMHXD3R
  RX5gP7kuu2KGMg==
  -----END CERTIFICATE-----
PEM
# Figure 1, third block — the root CA (the PEM form of FIG3_MEMBER2).
# Figure 1, third block — the root CA (the PEM form of FIG3_MEMBER2).
BLOCK3 = <<~PEM
  -----BEGIN CERTIFICATE-----
  MIICBjCCAaygAwIBAgIJAKS0yiqKtlhoMAoGCCqGSM49BAMCMFYxCzAJBgNVBAYT
  AlVTMRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdz
  IEF1dGhlbnRpY2F0ZSBSb290IEF1dGhvcml0eTAeFw0yMDAxMTQyMTI1NDVaFw00
  MDAxMDkyMTI1NDVaMFYxCzAJBgNVBAYTAlVTMRswGQYDVQQKDBJMZXQncyBBdXRo
  ZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBSb290IEF1dGhv
  cml0eTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFoaHU+Z5bPKmGzlYXtCf+E6
  HYj62fORaHDOrt+yyh3H/rTcs7ynFfGn+gyFsrSP3Ez88rajv+U2NfD0o0uZ4Pmj
  YzBhMB0GA1UdDgQWBBTEA2Q6eecKu9g9yb5glbkhhVINGDAfBgNVHSMEGDAWgBTE
  A2Q6eecKu9g9yb5glbkhhVINGDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQE
  AwIBhjAKBggqhkjOPQQDAgNIADBFAiEAmAeg1ycKHriqHnaD4M/UDBpQRpkmdcRF
  YGMg1Qyrkx4CIB4ivz3wQcQkGhcsUZ1SOImd/lq1Q0FLf09rGfLQPWDc
  -----END CERTIFICATE-----
PEM
MALFORMED_SAMPLE = "!!"
MEMBER_FALL_SAMPLE = ":aGVsbG8=:, 5"
QUICK = ENV["BENCH_QUICK"]

# One settled call's object count, GC off over the timed batch.
def objects_per_call(call, times = 10_000)
  call.call
  GC.start
  GC.disable
  before = GC.stat(:total_allocated_objects)
  times.times { call.call }
  (GC.stat(:total_allocated_objects) - before) / times.to_f
ensure
  GC.enable
end

# The budget paths on their budget inputs — the Cert parse (with its
# malformed fall to nil, the strict parse and the valid? mirror),
# construction and emit; the Chain parse (the whole value, the
# split-line form, the malformed fall to the shared empty value, the
# member-violation fall, the strict parse and the mirror),
# construction, emit and the split; the four PEM helpers.
cert = Fast::ClientCert::Cert.parse(FIG2)
chain = Fast::ClientCert::Chain.parse(FIG3)
chain_lines = [FIG3_MEMBER1, " #{FIG3_MEMBER2}"]
der = "hello".b
ders = ["hello".b, "world".b]
blocks = [BLOCK2, BLOCK3]

operations = {
  "Cert.parse" => -> { Fast::ClientCert::Cert.parse(FIG2) },
  "Cert.parse (malformed)" => -> { Fast::ClientCert::Cert.parse(MALFORMED_SAMPLE) },
  "Cert.parse!" => -> { Fast::ClientCert::Cert.parse!(FIG2) },
  "Cert.valid?" => -> { Fast::ClientCert::Cert.valid?(FIG2) },
  "Cert.new" => -> { Fast::ClientCert::Cert.new(der) },
  "Cert#to_s" => -> { cert.to_s },
  "Chain.parse" => -> { Fast::ClientCert::Chain.parse(FIG3) },
  "Chain.parse (split lines)" => -> { Fast::ClientCert::Chain.parse(chain_lines) },
  "Chain.parse (malformed)" => -> { Fast::ClientCert::Chain.parse(MALFORMED_SAMPLE) },
  "Chain.parse (member fall)" => -> { Fast::ClientCert::Chain.parse(MEMBER_FALL_SAMPLE) },
  "Chain.parse!" => -> { Fast::ClientCert::Chain.parse!(FIG3) },
  "Chain.valid?" => -> { Fast::ClientCert::Chain.valid?(FIG3) },
  "Chain.new" => -> { Fast::ClientCert::Chain.new(ders) },
  "Chain#to_s" => -> { chain.to_s },
  "Chain#split" => -> { chain.split(1) },
  "pem_to_field" => -> { Fast::ClientCert.pem_to_field(BLOCK1) },
  "field_to_pem" => -> { Fast::ClientCert.field_to_pem(FIG2) },
  "pems_to_field" => -> { Fast::ClientCert.pems_to_field(blocks) },
  "field_to_pems" => -> { Fast::ClientCert.field_to_pems(FIG3) }
}

puts "#{RUBY_DESCRIPTION}; fast-client-cert #{Fast::ClientCert::VERSION}"
puts "the numbers hold fast-client-cert to its own budgets (the objects/call column); i/s is indicative"

report = Benchmark.ips do |x|
  x.quiet = true
  x.config(time: QUICK ? 0.5 : 5, warmup: QUICK ? 0.2 : 1)
  operations.each { |name, call| x.report(name, &call) }
end

# The doc's results table: operation, comma-grouped i/s, ±% and objects/call.
def grouped(number)
  number.round.to_s.gsub(/(\d)(?=(\d{3})+\z)/, "\\1,")
end

puts "| operation | i/s | ±% | objects/call |"
puts "|---|---|---|---|"
report.entries.each do |entry|
  objects = objects_per_call(operations.fetch(entry.label))
  error = entry.stats.error / entry.ips * 100
  puts format("| %<label>s | %<ips>s | %<error>.2f | %<objects>.2f |",
              label: entry.label, ips: grouped(entry.ips), error: error, objects: objects)
end
