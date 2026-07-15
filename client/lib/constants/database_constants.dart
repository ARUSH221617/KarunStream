class HeroTable {
  HeroTable._();

  static const String tableName = 'heroes';

  static const String columnId = 'id';
  static const String columnName = 'name';
  static const String columnDescription = 'description';
  static const String columnImageUrl = 'imageUrl';
  static const String columnIsFavorite = 'isFavorite';
  static const String columnPower = 'power';
  static const String columnLastUpdated = 'lastUpdated';

  static const String createTableQuery = '''
    CREATE TABLE IF NOT EXISTS $tableName (
      $columnId TEXT PRIMARY KEY,
      $columnName TEXT NOT NULL,
      $columnDescription TEXT NOT NULL,
      $columnImageUrl TEXT NOT NULL,
      $columnIsFavorite INTEGER NOT NULL DEFAULT 0,
      $columnPower INTEGER NOT NULL DEFAULT 0,
      $columnLastUpdated INTEGER
    )
  ''';
}

class ProfileTable {
  ProfileTable._();

  static const String tableName = 'profile';

  static const String columnId = 'id';
  static const String columnEmail = 'email';
  static const String columnPassword = 'password';
  static const String columnName = 'name';
  static const String columnJob = 'job';
  static const String columnAvatar = 'avatar';
  static const String columnDiamond = 'diamond';
  static const String columnExpiryDatePremium = 'expiry_date_premium';
  static const String columnIsLifetimePremium = 'is_lifetime_premium';

  static const String createTableQuery = '''
    CREATE TABLE IF NOT EXISTS $tableName (
      $columnId TEXT PRIMARY KEY,
      $columnEmail TEXT UNIQUE NOT NULL,
      $columnPassword TEXT NOT NULL,
      $columnName TEXT,
      $columnJob TEXT,
      $columnAvatar TEXT,
      $columnDiamond INTEGER DEFAULT 0,
      $columnExpiryDatePremium TEXT,
      $columnIsLifetimePremium INTEGER DEFAULT 0
    )
  ''';
}
