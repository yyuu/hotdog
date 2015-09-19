# Hotdog

[![Build Status](https://travis-ci.org/yyuu/hotdog.svg)](https://travis-ci.org/yyuu/hotdog)

Yet another command-line tools for [Datadog](https://www.datadoghq.com/).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hotdog'
```

And then execute:

```sh
$ bundle
```

Or install it yourself as:

```
$ gem install hotdog
```

Then, setup API key and application key of Datadog. The keys can be configured in environment variables or configuration file.

```sh
export DATADOG_API_KEY="abcdefghijklmnopqrstuvwxyzabcdef"
export DATADOG_APPLICATION_KEY="abcdefghijklmnopqrstuvwxyzabcdefghijklmn"
```

Or,

```
$ mkdir ~/.hotdog
$ cat <<EOF > ~/.hotdog/config.yml
---
api_key: abcdefghijklmnopqrstuvwxyzabcdef
application_key: abcdefghijklmnopqrstuvwxyzabcdefghijklmn
EOF
```

## Usage

List all registered hosts.

```sh
$ hotdog ls
i-02605a79
i-02d78cec
i-03cb56ed
i-03dabcef
i-069e282c
```

List all registered hosts with associated tags and headers.

```sh
$ hotdog ls -h -l
host       security-group name              availability-zone instance-type image        region    kernel      
---------- -------------- ----------------- ----------------- ------------- ------------ --------- ------------
i-02605a79 sg-89bfe710    web-staging       us-east-1a        m3.medium     ami-66089cdf us-east-1 aki-89ab75e1
i-02d78cec sg-89bfe710    web-production    us-east-1a        c3.4xlarge    ami-8bb3fc92 us-east-1 aki-89ab75e1
i-03cb56ed sg-89bfe710    web-production    us-east-1b        c3.4xlarge    ami-8bb3fc92 us-east-1 aki-89ab75e1
i-03dabcef sg-89bfe710    worker-production us-east-1a        c3.xlarge     ami-4032c1c8 us-east-1 aki-89ab75e1
i-069e282c sg-89bfe710    worker-staging    us-east-1a        t2.micro      ami-384c8480 us-east-1 aki-89ab75e1
```

Display hosts with specific attributes.

```sh
$ hotdog ls -h -a host -a name
host       name             
---------- -----------------
i-02605a79 web-staging      
i-02d78cec web-production   
i-03cb56ed web-production   
i-03dabcef worker-production
i-069e282c worker-staging   
```

Search hosts matching to specified tags and values.

```sh
$ hotdog search availability-zone:us-east-1b and 'name:web-*'
i-03cb56ed
```

Login to the matching host using ssh.

```sh
$ hotdog ssh availability-zone:us-east-1b and 'name:web-*' -t public_ipv4 -u username
```


## Expression

Acceptable expressions in pseudo BNF.

```
expression: expression0
          ;

expression0: expression1 "and" expression
           | expression1 "or" expression
           | expression1 "xor" expression
           | expression1
           ;

expression1: "not" expression
           | expression2
           ;

expression2: expression3 expression
           | expression3
           ;

expression3: expression4 "&&" expression
           | expression4 "||" expression
           | expression4 '&' expression
           | expression4 '^' expression
           | expression4 '|' expression
           | expression4
           ;

expression4: '!' atom
           | '~' atom
           | '!' expression
           | '~' expression
           | atom
           ;

atom: '(' expression ')'
    | IDENTIFIER separator ATTRIBUTE
    | IDENTIFIER separator
    | separator ATTRIBUTE
    | IDENTIFIER
    | ATTRIBUTE
    ;

separator: ':'
         | '='
         ;
```


## Contributing

1. Fork it ( https://github.com/yyuu/hotdog/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
