//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// WARNING
// =======
//
// This is an example certificate/private key. DEFINITELY DO NOT USE THESE IN PRODUCTION.
// The only reason they are here is to make the example server easier to start.

let samplePemCert = """
    -----BEGIN CERTIFICATE-----
    MIIC+zCCAeOgAwIBAgIJANG6W1v704/aMA0GCSqGSIb3DQEBBQUAMBQxEjAQBgNV
    BAMMCWxvY2FsaG9zdDAeFw0xOTA4MDExMDMzMjhaFw0yOTA3MjkxMDMzMjhaMBQx
    EjAQBgNVBAMMCWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
    ggEBAMLw9InBMGKUNZKXFIpjUYt+Tby42GRQaRFmHfUrlYkvI9L7i9cLqltX/Pta
    XL9zISJIEgIgOW1R3pQ4xRP3xC+C3lKpo5lnD9gaMnDIsXhXLQzvTo+tFgtShXsU
    /xGl4U2Oc2BbPmydd+sfOPKXOYk/0TJsuSb1U5pA8FClyJUrUlykHkN120s5GhfA
    P2KYP+RMZuaW7gNlDEhiInqYUxBpLE+qutAYIDdpKWgxmHKW1oLhZ70TT1Zs7tUI
    22ydjo81vbtB4214EDX0KRRBep+Kq9vTigss34CwhYvyhaCP6l305Z9Vjtu1q1vp
    a3nfMeVtcg6JDn3eogv0CevZMc0CAwEAAaNQME4wHQYDVR0OBBYEFK6KIoQAlLog
    bBT3snTQ22x5gmXQMB8GA1UdIwQYMBaAFK6KIoQAlLogbBT3snTQ22x5gmXQMAwG
    A1UdEwQFMAMBAf8wDQYJKoZIhvcNAQEFBQADggEBAEgoqcGDMriG4cCxWzuiXuV7
    3TthA8TbdHQOeucNvXt9b3HUG1fQo7a0Tv4X3136SfCy3SsXXJr43snzVUK9SuNb
    ntqhAOIudZNw8KSwe+qJwmSEO4y3Lwr5pFfUUkGkV4K86wv3LmBpo3jep5hbkpAc
    kvbzTynFrOILV0TaDkF46KHIoyAb5vPneapdW7rXbX1Jba3jo9PyvHRMeoh/I8zt
    4g+Je2PpH1TJ/GT9dmYhYgJaIssVpv/fWkWphVXwMmpqiH9vEbln8piXHxvCj9XU
    y7uc6N1VUvIvygzUsR+20wjODoGiXp0g0cj+38n3oG5S9rBd1iGEPMAA/2lQS/0=
    -----END CERTIFICATE-----
    """

let samplePKCS8PemPrivateKey = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEowIBAAKCAQEAwvD0icEwYpQ1kpcUimNRi35NvLjYZFBpEWYd9SuViS8j0vuL
    1wuqW1f8+1pcv3MhIkgSAiA5bVHelDjFE/fEL4LeUqmjmWcP2BoycMixeFctDO9O
    j60WC1KFexT/EaXhTY5zYFs+bJ136x848pc5iT/RMmy5JvVTmkDwUKXIlStSXKQe
    Q3XbSzkaF8A/Ypg/5Exm5pbuA2UMSGIiephTEGksT6q60BggN2kpaDGYcpbWguFn
    vRNPVmzu1QjbbJ2OjzW9u0HjbXgQNfQpFEF6n4qr29OKCyzfgLCFi/KFoI/qXfTl
    n1WO27WrW+lred8x5W1yDokOfd6iC/QJ69kxzQIDAQABAoIBAQCX+KZ62cuxnh8h
    l3wg4oqIt788l9HCallugfBq2D5sQv6nlQiQbfyx1ydWgDx71/IFuq+nTp3WVpOx
    c4xYI7ii3WAaizsJ9SmJ6+pUuHB6A2QQiGLzaRkdXIjIyjaK+IlrH9lcTeWdYSlC
    eAW6QSBOmhypNc8lyu0Q/P0bshJsDow5iuy3d8PeT3klxgRPWjgjLZj0eUA0Orfp
    s6rC3t7wq8S8+YscKNS6dO0Vp2rF5ZHYYZ9kG5Y0PbAx24hDoYcgMJYJSw5LuR9D
    TkNcstHI8aKM7t9TZN0eXeLmzKXAbkD0uyaK0ZwI2panFDBjkjnkwS7FjHDusk1S
    Or36zCV1AoGBAOj8ALqa5y4HHl2QF8+dkH7eEFnKmExd1YX90eUuO1v7oTW4iQN+
    Z/me45exNDrG27+w8JqF66zH+WAfHv5Va0AUnTuFAyBmOEqit0m2vFzOLBgDGub1
    xOVYQQ5LetIbiXYU4H3IQDSO+UY27u1yYsgYMrO1qiyGgEkFSbK5xh6HAoGBANYy
    3rv9ULu3ZzeLqmkO+uYxBaEzAzubahgcDniKrsKfLVywYlF1bzplgT9OdGRkwMR8
    K7K5s+6ehrIu8pOadP1fZO7GC7w5lYypbrH74E7mBXSP53NOOebKYpojPhxjMrtI
    HLOxGg742WY5MTtDZ81Va0TrhErb4PxccVQEIY4LAoGAc8TMw+y21Ps6jnlMK6D6
    rN/BNiziUogJ0qPWCVBYtJMrftssUe0c0z+tjbHC5zXq+ax9UfsbqWZQtv+f0fc1
    7MiRfILSk+XXMNb7xogjvuW/qUrZskwLQ38ADI9a/04pluA20KmRpcwpd0dSn/BH
    v2+uufeaELfgxOf4v/Npy78CgYBqmqzB8QQCOPg069znJp52fEVqAgKE4wd9clE9
    awApOqGP9PUpx4GRFb2qrTg+Uuqhn478B3Jmux0ch0MRdRjulVCdiZGDn0Ev3Y+L
    I2lyuwZSCeDOQUuN8oH6Zrnd1P0FupEWWXk3pGBGgQZgkV6TEgUuKu0PeLlTwApj
    Hx84GwKBgHWqSoiaBml/KX+GBUDu8Yp0v+7dkNaiU/RVaSEOFl2wHkJ+bq4V+DX1
    lgofMC2QvBrSinEjHrQPZILl+lOq/ppDcnxhY/3bljsutcgHhIT7PKYDOxFqflMi
    ahwyQwRg2oQ2rBrBevgOKFEuIV62WfDYXi8SlT8QaZpTt2r4PYt4
    -----END RSA PRIVATE KEY-----
    """
