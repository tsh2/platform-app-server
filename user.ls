require! { crypto, './db.ls', './email.ls', './session.ls': sess }

gen-hex = (bytes, callback) !->
  ex, buf <-! crypto.random-bytes bytes
  if ex then throw ex
  callback buf.to-string \hex

encrypt = do
  hash = (string, salt) ->
    sha256 = crypto.create-hash \sha256
    sha256.update salt + string
    salt + sha256.digest \hex

  (string, salt, callback) !->
    if salt
      callback hash string, salt
      return

    hex <-! gen-hex 32bytes
    callback hash string, hex

users = null

handlers =

  #########################################################################

  # TODO: Check email format, name length, and password complexity
  register: (session, data, callback) !->
    if not data.username or not data.password
      callback error: 11
      return

    err, docs <-! users.find { data.email }
      .to-array!

    if docs.length > 0
      callback error: 12
      return

    err, docs <-! users.find { data.username }
      .to-array!

    if docs.length > 0
      callback error: 13
      return

    password <-! encrypt data.password, null

    rand-hash <-! gen-hex 32bytes

    err <-! users.insert { data.email, data.username, password, unverified: true, rand-hash }
    if err then throw err

    email.verify data.email, data.username, rand-hash

    callback success: true

  #########################################################################

  login: (session, data, callback) !->
    if not data.username or not data.password
      callback error: 11
      return

    err, docs <-! users.find { $or: [ { email: data.username }, { data.username } ] }
      .to-array!

    if docs.length is 0
      callback error: 14
      return

    password <-! encrypt data.password, docs[0].password.slice 0, 64
    if password is not docs[0].password
      callback error: 15
      return

    session-ID <-! gen-hex 32bytes
    session.id = session-ID
    session.user = docs[0]
    sess.cache[session-ID] = session

    callback success: true session-ID

  #########################################################################

  whoami: (session, data, callback) !->
    callback { session.id }

  #########################################################################

  whois: (session, data, callback) !->
    try oid = new db.ObjectID data._id catch then callback error: 31; return

    err, doc <-! users.find-one { $or: [ { _id: oid }, { data.username } ] }

    unless doc?
      callback error: 31
      return

    callback { doc._id, doc.username }

  #########################################################################

  logout: (session, data, callback) !->
    if session.id? and session.id of sess.cache
      delete! sess.cache[session.id]
    callback success: true

  #########################################################################

  verify: (session, data, callback) !->
    if not data.email or not data.hash
      callback redirect: \/
      return

    err, docs <-! users.find { data.email }
      .to-array!

    if docs.length < 1 or not docs[0].rand-hash? or data.hash is not docs[0].rand-hash
      # TODO: Make human-readable
      callback error: 18
      return

    err <-! users.update { _id: docs[0]._id } { $unset: { unverified: '', rand-hash: '' } }
    if err then throw err

    callback success: true

  #########################################################################

export get-handlers = (callback) !-> if users? then callback handlers else db.collection \users !-> users := it; callback handlers