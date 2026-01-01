/**
 * @description       : Selector class to fetch User Records1
 * @author            : Govinda.kumar.p@accenture.com
 * @group             :
 * @last modified on  : 29-03-2025
 * @last modified by  : venkatesh.chitrala@accenture.com
**/

public without sharing class CS_UserSelector extends SPLIB.so_SObjectSelector  {

    /**
    * @description : Method containing fields list of User Object which will be fetched as default
    * @author sourav.das.adhikary@accenture.com | 10-02-2024
    * @return List<Schema.SObjectField>
    **/

    public CS_UserSelector(){
        super(
      false, // Do not include FieldSet fields
      false, // Do not enforce Object level security
      false
    ); // Do not enforce Field level security
    }

    public override List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
            User.Id
        };
      }

    /**
     * @description : Method defining the SObjectType this selector class belongs to User Object
    * @author sourav.das.adhikary@accenture.com | 10-02-2024
    * @return Schema.SObjectType
    **/
    public override Schema.SObjectType getSObjectType() {
    return User.sObjectType;
    }

    public List<User> selectFieldsFromUser(
        Set<String> fieldNames,
        string conditions
    ) {

        return (List<User>) Database.query(
        newQueryFactory()
            .selectFields(fieldNames)
            .setCondition(conditions)
            .toSOQL()
        );
  }

    /**
   * @description : method to get user record fields based on user name
   * @author Accenture | 03-26-2025
   * @param fieldNames
   * @param idSet,limit Value
   * @return List<User>
   **/
    public List<User> selectFieldsFromUserRecord(
        Set<String> fieldNames,
        string conditions,
        Integer limitvalue
    ) {

        return (List<User>) Database.query(
        newQueryFactory()
            .selectFields(fieldNames)
            .setCondition(conditions)
            .setLimit(limitvalue)
            .toSOQL()
        );
  }
}