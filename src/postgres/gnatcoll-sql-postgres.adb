------------------------------------------------------------------------------
--                             G N A T C O L L                              --
--                                                                          --
--                     Copyright (C) 2005-2015, AdaCore                     --
--                                                                          --
-- This library is free software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License  as published by the Free --
-- Software  Foundation;  either version 3,  or (at your  option) any later --
-- version. This library is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE.                            --
--                                                                          --
-- As a special exception under Section 7 of GPL version 3, you are granted --
-- additional permissions described in the GCC Runtime Library Exception,   --
-- version 3.1, as published by the Free Software Foundation.               --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Unchecked_Deallocation;
with GNATCOLL.SQL.Postgres.Builder;

package body GNATCOLL.SQL.Postgres is

   N_OID : aliased constant String := "OID";

   Comparison_Regexp : aliased constant String := " ~* ";

   type Query_Postgres_Contents is new Query_Contents with record
      Base  : SQL_Query;
      Extra : SQL_PG_Extension_Access;
   end record;
   overriding procedure Free (Self : in out Query_Postgres_Contents);
   overriding function To_String
     (Self   : Query_Postgres_Contents;
      Format : Formatter'Class) return Unbounded_String;
   overriding procedure Auto_Complete
     (Self                   : in out Query_Postgres_Contents;
      Auto_Complete_From     : Boolean := True;
      Auto_Complete_Group_By : Boolean := True);
   --  Supports adding a suffix string to the base_query

   type SQL_PG_For_Update is new SQL_PG_Extension with record
      Tables : SQL_Table_List := Empty_Table_List;
      --  List of updated tables (empty means ALL tables in query)

      No_Wait : Boolean := False;
      --  Set True if NO WAIT
   end record;
   overriding function To_String
     (Self   : SQL_PG_For_Update;
      Format : Formatter'Class) return Unbounded_String;
   --  Extensions for UPDATE

   type SQL_PG_Returning is new SQL_PG_Extension with record
      Returning : SQL_Field_List;
   end record;
   overriding function To_String
     (Self   : SQL_PG_Returning;
      Format : Formatter'Class) return Unbounded_String;
   --  Extensions for SELECT

   ----------
   -- Free --
   ----------

   overriding procedure Free (Self : in out Query_Postgres_Contents) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
         (SQL_PG_Extension'Class, SQL_PG_Extension_Access);
   begin
      Unchecked_Free (Self.Extra);
      Free (Query_Contents (Self));
   end Free;

   ---------------
   -- To_String --
   ---------------

   overriding function To_String
     (Self   : Query_Postgres_Contents;
      Format : Formatter'Class) return Unbounded_String is
   begin
      return To_String (Self.Base, Format)
          & To_String (Self.Extra.all, Format);
   end To_String;

   -------------------
   -- Auto_Complete --
   -------------------

   overriding procedure Auto_Complete
     (Self                   : in out Query_Postgres_Contents;
      Auto_Complete_From     : Boolean := True;
      Auto_Complete_Group_By : Boolean := True) is
   begin
      Auto_Complete (Self.Base, Auto_Complete_From, Auto_Complete_Group_By);
   end Auto_Complete;

   -----------
   -- Setup --
   -----------

   function Setup
     (Database      : String;
      User          : String := "";
      Host          : String := "";
      Password      : String := "";
      Port          : Integer := -1;
      SSL           : SSL_Mode := Allow;
      Cache_Support : Boolean := True;
      Errors        : access Error_Reporter'Class := null)
      return Database_Description
   is
      Result : Postgres_Description_Access;
   begin
      if not GNATCOLL.SQL.Postgres.Builder.Has_Postgresql_Support then
         return null;
      end if;

      Result := new Postgres_Description
        (Caching => Cache_Support, Errors => Errors);
      Result.SSL      := SSL;
      Result.Dbname   := new String'(Database);
      Result.User     := new String'(User);
      Result.Password := new String'(Password);
      Result.Port     := Port;
      Result.Host := new String'(Host);

      return Database_Description (Result);
   end Setup;

   ----------------------
   -- Build_Connection --
   ----------------------

   overriding function Build_Connection
     (Self : access Postgres_Description) return Database_Connection
   is
      DB : Database_Connection;
   begin
      DB := GNATCOLL.SQL.Postgres.Builder.Build_Connection (Self);
      Reset_Connection (DB);
      return DB;
   end Build_Connection;

   ---------------
   -- OID_Field --
   ---------------

   function OID_Field (Table : SQL_Table'Class) return SQL_Field_Integer is
   begin
      return SQL_Field_Integer'
        (Table          => Table.Table_Name,
         Instance       => Table.Instance,
         Instance_Index => Table.Instance_Index,
         Name           => N_OID'Access);
   end OID_Field;

   ----------
   -- Free --
   ----------

   overriding procedure Free (Description : in out Postgres_Description) is
   begin
      GNAT.Strings.Free (Description.Host);
      GNAT.Strings.Free (Description.User);
      GNAT.Strings.Free (Description.Dbname);
      GNAT.Strings.Free (Description.Password);
   end Free;

   ------------
   -- Regexp --
   ------------

   function Regexp
     (Self : Text_Fields.Field'Class;
      Str  : String) return SQL_Criteria is
   begin
      return Compare (Self, Expression (Str), Comparison_Regexp'Access);
   end Regexp;

   ----------------
   -- For_Update --
   ----------------

   function For_Update
     (Tables  : SQL_Table_List := Empty_Table_List;
      No_Wait : Boolean := False) return SQL_PG_Extension'Class
   is
   begin
      return SQL_PG_For_Update'(Tables => Tables, No_Wait => No_Wait);
   end For_Update;

   ---------------
   -- Returning --
   ---------------

   function Returning
     (Fields : SQL_Field_List) return SQL_PG_Extension'Class
   is
   begin
      return SQL_PG_Returning'(Returning => Fields);
   end Returning;

   ---------
   -- "&" --
   ---------

   function "&"
     (Query     : SQL_Query;
      Extension : SQL_PG_Extension'Class) return SQL_Query
   is
      Data : Query_Postgres_Contents;
      Q    : SQL_Query;
   begin
      if Query.Get.all in Query_Postgres_Contents'Class then
         --  Merge the information with what has already been set.
         --  For now, assume that Extension is the same type as was
         --  already set, since we have a single extension for Update
         --  and a single extension for Select. Any other combination
         --  is invalid.

         if Extension in SQL_PG_For_Update'Class then
            declare
               Orig : SQL_PG_For_Update'Class renames
                  SQL_PG_For_Update'Class
                    (Query_Postgres_Contents'Class (Query.Get.all).Extra.all);
            begin
               Orig.Tables := Orig.Tables &
                  SQL_PG_For_Update'Class (Extension).Tables;
               Orig.No_Wait := Orig.No_Wait or else
                  SQL_PG_For_Update'Class (Extension).No_Wait;
            end;

         else
            declare
               Orig : SQL_PG_Returning'Class renames
                  SQL_PG_Returning'Class
                    (Query_Postgres_Contents'Class (Query.Get.all).Extra.all);
            begin
               Orig.Returning := Orig.Returning &
                   SQL_PG_Returning'Class (Extension).Returning;
            end;
         end if;

         return Query;

      else
         Data.Base := Query;
         Data.Extra := new SQL_PG_Extension'Class'(Extension);
         Q.Set (Data);
         return Q;
      end if;
   end "&";

   ---------------
   -- To_String --
   ---------------

   overriding function To_String
     (Self   : SQL_PG_For_Update;
      Format : Formatter'Class) return Unbounded_String
   is
      Result : Unbounded_String;
   begin
      Append (Result, " FOR UPDATE");
      if Self.Tables /= Empty_Table_List then
         Append (Result, " OF ");
         Append (Result, To_String (Self.Tables, Format));
      end if;

      if Self.No_Wait then
         Append (Result, " NO WAIT");
      end if;

      return Result;
   end To_String;

   ---------------
   -- To_String --
   ---------------

   overriding function To_String
     (Self   : SQL_PG_Returning;
      Format : Formatter'Class) return Unbounded_String
   is
      Result : Unbounded_String;
   begin
      Append (Result, " RETURNING ");
      Append (Result, To_String (Self.Returning, Format, Long => True));
      return Result;
   end To_String;

end GNATCOLL.SQL.Postgres;
