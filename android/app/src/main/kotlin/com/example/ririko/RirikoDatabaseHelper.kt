package com.example.ririko

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class RirikoDatabaseHelper private constructor(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE logs(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              packageName TEXT NOT NULL,
              time TEXT NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE transactions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fingerprint TEXT NOT NULL UNIQUE,
              amount REAL NOT NULL,
              direction TEXT NOT NULL,
              sourceApp TEXT NOT NULL,
              sourceTitle TEXT NOT NULL,
              sourceContent TEXT NOT NULL,
              counterparty TEXT,
              category TEXT NOT NULL,
              note TEXT,
              happenedAt TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS transactions(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  fingerprint TEXT NOT NULL UNIQUE,
                  amount REAL NOT NULL,
                  direction TEXT NOT NULL,
                  sourceApp TEXT NOT NULL,
                  sourceTitle TEXT NOT NULL,
                  sourceContent TEXT NOT NULL,
                  counterparty TEXT,
                  category TEXT NOT NULL,
                  note TEXT,
                  happenedAt TEXT NOT NULL,
                  createdAt TEXT NOT NULL
                )
                """.trimIndent(),
            )
        }
    }

    fun insertNotificationLog(
        title: String,
        content: String,
        packageName: String,
        time: String,
    ) {
        writableDatabase.insert(
            "logs",
            null,
            ContentValues().apply {
                put("title", title)
                put("content", content)
                put("packageName", packageName)
                put("time", time)
            },
        )
    }

    fun insertTransaction(transaction: NativeParsedTransaction, createdAt: String) {
        writableDatabase.insertWithOnConflict(
            "transactions",
            null,
            ContentValues().apply {
                put("fingerprint", transaction.fingerprint)
                put("amount", transaction.amount)
                put("direction", transaction.direction)
                put("sourceApp", transaction.sourceApp)
                put("sourceTitle", transaction.title)
                put("sourceContent", transaction.content)
                put("counterparty", transaction.counterparty)
                put("category", transaction.category)
                put("note", transaction.note)
                put("happenedAt", transaction.happenedAt)
                put("createdAt", createdAt)
            },
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    companion object {
        private const val DATABASE_NAME = "ririko.db"
        private const val DATABASE_VERSION = 2

        @Volatile
        private var instance: RirikoDatabaseHelper? = null

        fun getInstance(context: Context): RirikoDatabaseHelper {
            return instance ?: synchronized(this) {
                instance ?: RirikoDatabaseHelper(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }
}
