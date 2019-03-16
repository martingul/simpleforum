module Users
  def self.signup(username, password)
    password_hash = Auth.hash(password)

    # store a new user instance and get the uid back
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'INSERT INTO users(username, password)
      VALUES($1, $2)
      RETURNING id AS uid')
    result = $db.exec_prepared(seed, [username, password_hash])
    # TODO check result
    uid = result[0]['uid']
    result.clear

    return View.finalize('login', 201, created: true, username_trial: username)
  rescue PG::Error => e
    sqlstate = e.result.error_field(PG::Result::PG_DIAG_SQLSTATE)

    if sqlstate == '23505' # unique username constraint error
      return View.finalize('login', 400, {
        username: username, username_taken: true
      })
    end
  end

  def self.get_user(username, session)
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'SELECT users.id, users.date_created
      FROM users
      WHERE users.username = $1 LIMIT 1')
    result = $db.exec_prepared(seed, [username]) # TODO check result

    return Routes.not_found if result.values.empty? # user not found

    id = result.column_values(0)[0]
    date_created = result.column_values(1)[0]
    result.clear
    t_created = Time.parse(date_created).strftime("%B %e %Y")

    user = { id: id, username: username, date_created: t_created }
    new_threads = get_history(user, 'date_created')
    top_threads = get_history(user, 'children')

    return View.finalize('user', 200, {
      user: user,
      new_threads: new_threads,
      top_threads: top_threads,
      session: session
    })
  end

  def self.get_history(user, sort = 'date_created')
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    seed = Random.new_seed.to_s

    statement = <<~SQL
      SELECT threads.id, threads.text, threads.ext,
      threads.parent, threads.children, threads.date_created
      FROM threads
      WHERE threads.author = $1
    SQL

    if sort == 'date_created'
      # newest threads
      statement += <<~SQL
        ORDER BY threads.date_created DESC LIMIT 20
      SQL
    elsif sort == 'children'
      # threads with most children
      statement += <<~SQL
        ORDER BY cardinality(threads.children) DESC LIMIT 20
      SQL
    end

    $db.prepare(seed, statement)
    result = $db.exec_prepared(seed, [user[:id]])

    threads = []
    result.each_row { |row|
      threads.push(Render::Thread.new(
        hash: hashids.encode(row[0].to_i),
        author: user[:username],
        text: row[1],
        ext: row[2],
        parent: row[3],
        children: row[4].tr('{}', '').split(',').map{ |c| c.to_i },
        date_created: Threads.date_as_sentence(row[5])
      ))
    }

    return threads
  end
end