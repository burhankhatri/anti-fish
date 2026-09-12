import Foundation
@testable import AntiFishCore

/// Builds stand-in WhatsApp databases. The schema is the subset AntiFish reads, captured from
/// WhatsApp Desktop 26.33's `sqlite_master`; every row here is invented and every JID is a short fake.
enum FixtureDB {
    static let chatDDL = """
    CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZISFROMME INTEGER, ZMESSAGETYPE INTEGER, ZCHATSESSION INTEGER, ZGROUPMEMBER INTEGER, ZMEDIAITEM INTEGER, ZMESSAGEDATE TIMESTAMP, ZFROMJID VARCHAR, ZTOJID VARCHAR);
    CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMOVIEDURATION INTEGER, ZMEDIALOCALPATH VARCHAR, ZMESSAGE INTEGER);
    CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZMEMBERJID VARCHAR, ZCHATSESSION INTEGER);
    CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID VARCHAR, ZPARTNERNAME VARCHAR, ZGROUPINFO INTEGER, ZCONTACTIDENTIFIER VARCHAR);
    CREATE TABLE ZWAPROFILEPUSHNAME (Z_PK INTEGER PRIMARY KEY, ZJID VARCHAR, ZPUSHNAME VARCHAR);
    CREATE TABLE ZWAPROFILEPICTUREITEM (Z_PK INTEGER PRIMARY KEY, ZJID VARCHAR, ZPATH VARCHAR);
    """

    static let contactsDDL = """
    CREATE TABLE ZWAADDRESSBOOKCONTACT (Z_PK INTEGER PRIMARY KEY, ZLID VARCHAR, ZPHONENUMBER VARCHAR, ZFULLNAME VARCHAR, ZGIVENNAME VARCHAR);
    """

    /// Session 1 is a 1:1 chat with 111@lid, saved as "Abdul Test".
    /// Session 2 is the group 200@g.us "Family", whose member 222@lid sends a note.
    /// Session 3 is an unsaved number 333@lid whose push name claims "Abdul".
    /// Messages: 1000 incoming 1:1 note (file), 1001 incoming group note (file),
    /// 1002 incoming note whose media has not downloaded, 1003 outgoing note (file), 1004 a video.
    static func seedChat(_ db: SQLiteDatabase) throws {
        try db.execute("""
            INSERT INTO ZWACHATSESSION VALUES
              (1,'111@lid','Abdul Test',NULL,'111@s.whatsapp.net'),
              (2,'200@g.us','Family',5,NULL),
              (3,'333@lid','+1 555 0100',NULL,NULL);
            INSERT INTO ZWAGROUPMEMBER VALUES (10,'222@lid',2);
            INSERT INTO ZWAMEDIAITEM VALUES
              (100,12,'Message/Media/111@lid/a/b/n1.opus',1000),
              (101,8,'Message/Media/200@g.us/c/d/n2.opus',1001),
              (102,5,NULL,1002),
              (103,30,'Message/Media/111@lid/e/f/mine.opus',1003);
            INSERT INTO ZWAMESSAGE (Z_PK,ZISFROMME,ZMESSAGETYPE,ZCHATSESSION,ZGROUPMEMBER,ZMEDIAITEM,ZMESSAGEDATE,ZFROMJID,ZTOJID) VALUES
              (1000,0,3,1,NULL,100,800000000,'111@lid',NULL),
              (1001,0,3,2,10,101,800000100,'200@g.us',NULL),
              (1002,0,3,1,NULL,102,800000200,'111@lid',NULL),
              (1003,1,3,1,NULL,103,800000300,NULL,'111@lid'),
              (1004,0,2,1,NULL,NULL,800000400,'111@lid',NULL);
            INSERT INTO ZWAPROFILEPUSHNAME VALUES (1,'111@lid','abdul'),(2,'222@lid','Karim'),(3,'333@lid','Abdul'),(4,'444@lid','Someone Else');
            INSERT INTO ZWAPROFILEPICTUREITEM VALUES (1,'111@lid','Media/Profile/111-1.thumb');
            """)
    }

    static func seedContacts(_ db: SQLiteDatabase) throws {
        try db.execute("""
            INSERT INTO ZWAADDRESSBOOKCONTACT VALUES
              (1,'111@lid','+15550111','Abdul Test','Abdul'),
              (2,'222@lid','+15550222','Karim Test','Karim');
            """)
    }

    /// Creates both databases inside one fresh temp directory laid out like the real container.
    static func standardPair() throws -> (root: URL, chat: URL, contacts: URL) {
        let root = try TestEnv.tempDir()
        let chat = root.appendingPathComponent("ChatStorage.sqlite")
        let contacts = root.appendingPathComponent("ContactsV2.sqlite")
        let chatDB = try SQLiteDatabase(url: chat, readOnly: false)
        try chatDB.execute(chatDDL)
        try seedChat(chatDB)
        let contactsDB = try SQLiteDatabase(url: contacts, readOnly: false)
        try contactsDB.execute(contactsDDL)
        try seedContacts(contactsDB)
        return (root, chat, contacts)
    }
}
