return {
  HEADERS = {
    HOST_OVERRIDE = "X-Host-Override",
    PROXY_LATENCY = "X-Proxy-Latency",
    UPSTREAM_LATENCY = "X-Upstream-Latency",
    CONSUMER_ID = "X-Consumer-ID",
    CONSUMER_USERNAME = "X-Consumer-Username",
    CREDENTIAL_USERNAME = "X-Credential-Username",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining",
    CONSUMER_GROUPS = "X-Consumer-Groups",
    FORWARDED_HOST = "X-Forwarded-Host",
    FORWARDED_PREFIX = "X-Forwarded-Prefix",
    AUTHENTICATED_SCOPE = "X-Authenticated-Scope",
    AUTHENTICATED_USERID = "X-Authenticated-Userid",
  },

  RATELIMIT = {
    PERIODS = {
      "second",
      "minute",
      "hour",
      "day",
      "month",
      "year"
    }
  },
  PLUGIN_NAME = {
    OAUTH2 = "oauth2"
  },
  TABLES = {
    META = 'meta',
    OAUTH2 = 'oauth2',
    CONSUMERS = 'consumers',
    OAUTH2_CREDENTIALS = 'oauth2_credentials',
    OAUTH2_TOKENS = 'oauth2_tokens',
    OAUTH2_AUTHORIZATION_CODE = 'oauth2_authorization_codes',

    BALANCER = 'balancer',
    BALANCER_URL = 'balancer_url',
    BALANCER_SERVERS = 'balancer_servers',

    LIMITING_RATE = 'limiting_rate',
    LIMITING_RATE_IDENTIFIER = 'limiting_rate_identifier'
  },

  AES = {
    IV = '',
    KEY = ''
  },

  VCG_HTTP_URLS = {
    VCG_USER_GET = '',
    VCG_USER_REGISTER = ''
  }

}