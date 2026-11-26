# frozen_string_literal: true

# The RFC 9440 Appendix A vectors, quoted verbatim from the RFC text
# (the one-space page gutter stripped, the display-only line breaks
# and added spaces unwrapped — "line breaks and extra spaces have
# been added to the field value in Figures 2 and 3 for display and
# formatting purposes only"). The three PEM certificate blocks of
# Figure 1 (base64 wrapped at 64 characters, every line
# newline-terminated) and the two field values they surgically
# produce: Figure 2 (the Client-Cert value) and Figure 3 (the
# Client-Cert-Chain value). Generated mechanically from the corpus,
# never hand-typed.

module ClientCertVectors
  # Figure 2 — the Client-Cert field value (the end-entity certificate).
  FIG2 = ":MIIBqDCCAU6gAwIBAgIBBzAKBggqhkjOPQQDAjA6MRswGQYDVQQKDBJMZXQncyBBdXR" \
         "oZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF0ZSBDQTAeFw0yMDAxMTQyMjU" \
         "1MzNaFw0yMTAxMjMyMjU1MzNaMA0xCzAJBgNVBAMMAkJDMFkwEwYHKoZIzj0CAQYIKoZ" \
         "Izj0DAQcDQgAE8YnXXfaUgmnMtOXU/IncWalRhebrXmckC8vdgJ1p5Be5F/3YC8OthxM" \
         "4+k1M6aEAEFcGzkJiNy6J84y7uzo9M6NyMHAwCQYDVR0TBAIwADAfBgNVHSMEGDAWgBR" \
         "m3WjLa38lbEYCuiCPct0ZaSED2DAOBgNVHQ8BAf8EBAMCBsAwEwYDVR0lBAwwCgYIKwY" \
         "BBQUHAwIwHQYDVR0RAQH/BBMwEYEPYmRjQGV4YW1wbGUuY29tMAoGCCqGSM49BAMCA0g" \
         "AMEUCIBHda/r1vaL6G3VliL4/Di6YK0Q6bMjeSkC3dFCOOB8TAiEAx/kHSB4urmiZ0NX" \
         "5r5XarmPk0wmuydBVoU4hBVZ1yhk=:"

  # Figure 3 — the Client-Cert-Chain field value (two Byte Sequences in TLS order).
  FIG3 = ":MIIB5jCCAYugAwIBAgIBFjAKBggqhkjOPQQDAjBWMQswCQYDVQQGEwJVUzEbMBkGA1U" \
         "ECgwSTGV0J3MgQXV0aGVudGljYXRlMSowKAYDVQQDDCFMZXQncyBBdXRoZW50aWNhdGU" \
         "gUm9vdCBBdXRob3JpdHkwHhcNMjAwMTE0MjEzMjMwWhcNMzAwMTExMjEzMjMwWjA6MRs" \
         "wGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF" \
         "0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJf+aA54RC5pyLAR5yfXVYmNpgd" \
         "+CGUTDp2KOGhc0gK91zxhHesEYkdXkpS2UN8Kati+yHtWCV3kkhCngGyv7RqjZjBkMB0" \
         "GA1UdDgQWBBRm3WjLa38lbEYCuiCPct0ZaSED2DAfBgNVHSMEGDAWgBTEA2Q6eecKu9g" \
         "9yb5glbkhhVINGDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjAKBgg" \
         "qhkjOPQQDAgNJADBGAiEA5pLvaFwRRkxomIAtDIwg9D7gC1xzxBl4r28EzmSO1pcCIQC" \
         "JUShpSXO9HDIQMUgH69fNDEMHXD3RRX5gP7kuu2KGMg==:, :MIICBjCCAaygAwIBAgI" \
         "JAKS0yiqKtlhoMAoGCCqGSM49BAMCMFYxCzAJBgNVBAYTAlVTMRswGQYDVQQKDBJMZXQ" \
         "ncyBBdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBSb290IEF" \
         "1dGhvcml0eTAeFw0yMDAxMTQyMTI1NDVaFw00MDAxMDkyMTI1NDVaMFYxCzAJBgNVBAY" \
         "TAlVTMRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF" \
         "1dGhlbnRpY2F0ZSBSb290IEF1dGhvcml0eTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0I" \
         "ABFoaHU+Z5bPKmGzlYXtCf+E6HYj62fORaHDOrt+yyh3H/rTcs7ynFfGn+gyFsrSP3Ez" \
         "88rajv+U2NfD0o0uZ4PmjYzBhMB0GA1UdDgQWBBTEA2Q6eecKu9g9yb5glbkhhVINGDA" \
         "fBgNVHSMEGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDAPBgNVHRMBAf8EBTADAQH/MA4" \
         "GA1UdDwEB/wQEAwIBhjAKBggqhkjOPQQDAgNIADBFAiEAmAeg1ycKHriqHnaD4M/UDBp" \
         "QRpkmdcRFYGMg1Qyrkx4CIB4ivz3wQcQkGhcsUZ1SOImd/lq1Q0FLf09rGfLQPWDc:"

  # Figure 3, first member — the intermediate CA certificate.
  FIG3_MEMBER1 = ":MIIB5jCCAYugAwIBAgIBFjAKBggqhkjOPQQDAjBWMQswCQYDVQQGEwJVUzEbMBkGA1U" \
                 "ECgwSTGV0J3MgQXV0aGVudGljYXRlMSowKAYDVQQDDCFMZXQncyBBdXRoZW50aWNhdGU" \
                 "gUm9vdCBBdXRob3JpdHkwHhcNMjAwMTE0MjEzMjMwWhcNMzAwMTExMjEzMjMwWjA6MRs" \
                 "wGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF" \
                 "0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJf+aA54RC5pyLAR5yfXVYmNpgd" \
                 "+CGUTDp2KOGhc0gK91zxhHesEYkdXkpS2UN8Kati+yHtWCV3kkhCngGyv7RqjZjBkMB0" \
                 "GA1UdDgQWBBRm3WjLa38lbEYCuiCPct0ZaSED2DAfBgNVHSMEGDAWgBTEA2Q6eecKu9g" \
                 "9yb5glbkhhVINGDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjAKBgg" \
                 "qhkjOPQQDAgNJADBGAiEA5pLvaFwRRkxomIAtDIwg9D7gC1xzxBl4r28EzmSO1pcCIQC" \
                 "JUShpSXO9HDIQMUgH69fNDEMHXD3RRX5gP7kuu2KGMg==:"

  # Figure 3, second member — the root CA certificate.
  FIG3_MEMBER2 = ":MIICBjCCAaygAwIBAgIJAKS0yiqKtlhoMAoGCCqGSM49BAMCMFYxCzAJBgNVBAYTAlV" \
                 "TMRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGh" \
                 "lbnRpY2F0ZSBSb290IEF1dGhvcml0eTAeFw0yMDAxMTQyMTI1NDVaFw00MDAxMDkyMTI" \
                 "1NDVaMFYxCzAJBgNVBAYTAlVTMRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxKjA" \
                 "oBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBSb290IEF1dGhvcml0eTBZMBMGByqGSM4" \
                 "9AgEGCCqGSM49AwEHA0IABFoaHU+Z5bPKmGzlYXtCf+E6HYj62fORaHDOrt+yyh3H/rT" \
                 "cs7ynFfGn+gyFsrSP3Ez88rajv+U2NfD0o0uZ4PmjYzBhMB0GA1UdDgQWBBTEA2Q6eec" \
                 "Ku9g9yb5glbkhhVINGDAfBgNVHSMEGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDAPBgN" \
                 "VHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAKBggqhkjOPQQDAgNIADBFAiEAmAe" \
                 "g1ycKHriqHnaD4M/UDBpQRpkmdcRFYGMg1Qyrkx4CIB4ivz3wQcQkGhcsUZ1SOImd/lq" \
                 "1Q0FLf09rGfLQPWDc:"

  # Figure 1, first block — the end-entity certificate (PEM form of FIG2).
  BLOCK1 = "-----BEGIN CERTIFICATE-----
MIIBqDCCAU6gAwIBAgIBBzAKBggqhkjOPQQDAjA6" \
           "MRswGQYDVQQKDBJMZXQncyBB
dXRoZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWV" \
           "kaWF0ZSBDQTAeFw0yMDAx
MTQyMjU1MzNaFw0yMTAxMjMyMjU1MzNaMA0xCzAJBgNVBA" \
           "MMAkJDMFkwEwYHKoZI
zj0CAQYIKoZIzj0DAQcDQgAE8YnXXfaUgmnMtOXU/IncWalRh" \
           "ebrXmckC8vdgJ1p
5Be5F/3YC8OthxM4+k1M6aEAEFcGzkJiNy6J84y7uzo9M6NyMHAw" \
           "CQYDVR0TBAIw
ADAfBgNVHSMEGDAWgBRm3WjLa38lbEYCuiCPct0ZaSED2DAOBgNVHQ8" \
           "BAf8EBAMC
BsAwEwYDVR0lBAwwCgYIKwYBBQUHAwIwHQYDVR0RAQH/BBMwEYEPYmRjQG" \
           "V4YW1w
bGUuY29tMAoGCCqGSM49BAMCA0gAMEUCIBHda/r1vaL6G3VliL4/Di6YK0Q6b" \
           "Mje
SkC3dFCOOB8TAiEAx/kHSB4urmiZ0NX5r5XarmPk0wmuydBVoU4hBVZ1yhk=
---" \
           "--END CERTIFICATE-----
"

  # Figure 1, second block — the intermediate CA (PEM form of FIG3_MEMBER1).
  BLOCK2 = "-----BEGIN CERTIFICATE-----
MIIB5jCCAYugAwIBAgIBFjAKBggqhkjOPQQDAjBW" \
           "MQswCQYDVQQGEwJVUzEbMBkG
A1UECgwSTGV0J3MgQXV0aGVudGljYXRlMSowKAYDVQQ" \
           "DDCFMZXQncyBBdXRoZW50
aWNhdGUgUm9vdCBBdXRob3JpdHkwHhcNMjAwMTE0MjEzMj" \
           "MwWhcNMzAwMTExMjEz
MjMwWjA6MRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxG" \
           "zAZBgNVBAMMEkxB
IEludGVybWVkaWF0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEH" \
           "A0IABJf+aA54
RC5pyLAR5yfXVYmNpgd+CGUTDp2KOGhc0gK91zxhHesEYkdXkpS2UN8" \
           "Kati+yHtW
CV3kkhCngGyv7RqjZjBkMB0GA1UdDgQWBBRm3WjLa38lbEYCuiCPct0ZaS" \
           "ED2DAf
BgNVHSMEGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDASBgNVHRMBAf8ECDAGA" \
           "QH/
AgEAMA4GA1UdDwEB/wQEAwIBhjAKBggqhkjOPQQDAgNJADBGAiEA5pLvaFwRRkxo" \
           "
mIAtDIwg9D7gC1xzxBl4r28EzmSO1pcCIQCJUShpSXO9HDIQMUgH69fNDEMHXD3R
RX" \
           "5gP7kuu2KGMg==
-----END CERTIFICATE-----
"

  # Figure 1, third block — the root CA (PEM form of FIG3_MEMBER2).
  BLOCK3 = "-----BEGIN CERTIFICATE-----
MIICBjCCAaygAwIBAgIJAKS0yiqKtlhoMAoGCCqG" \
           "SM49BAMCMFYxCzAJBgNVBAYT
AlVTMRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGU" \
           "xKjAoBgNVBAMMIUxldCdz
IEF1dGhlbnRpY2F0ZSBSb290IEF1dGhvcml0eTAeFw0yMD" \
           "AxMTQyMTI1NDVaFw00
MDAxMDkyMTI1NDVaMFYxCzAJBgNVBAYTAlVTMRswGQYDVQQKD" \
           "BJMZXQncyBBdXRo
ZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBS" \
           "b290IEF1dGhv
cml0eTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFoaHU+Z5bPKmGz" \
           "lYXtCf+E6
HYj62fORaHDOrt+yyh3H/rTcs7ynFfGn+gyFsrSP3Ez88rajv+U2NfD0o0" \
           "uZ4Pmj
YzBhMB0GA1UdDgQWBBTEA2Q6eecKu9g9yb5glbkhhVINGDAfBgNVHSMEGDAWg" \
           "BTE
A2Q6eecKu9g9yb5glbkhhVINGDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQE" \
           "
AwIBhjAKBggqhkjOPQQDAgNIADBFAiEAmAeg1ycKHriqHnaD4M/UDBpQRpkmdcRF
YG" \
           "Mg1Qyrkx4CIB4ivz3wQcQkGhcsUZ1SOImd/lq1Q0FLf09rGfLQPWDc
-----END CERT" \
           "IFICATE-----
"

  # The DER byte sizes of the three certificates (428 / 490 / 522).
  DER_BYTESIZES = [428, 490, 522].freeze

  # The DER sha256 digests of the three certificates, recorded from
  # the corpus for bytewise identity checks.
  DER_SHA256 = %w[
    bfaf1f7e070f9fa8dd62905f158da73f84a1136624fbafcc9393c8f7287a69eb
    e87df5b43ebf9b89ca2b2bbf31a4e7ad5a40d404cfbb2fcc1a403c2651285adc
    423ae95dc41cd26da9021ad4e6389baa77e0858607635ab085e91e5d1d947b83
  ].freeze
end
