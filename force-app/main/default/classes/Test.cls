public class Test {
    public static void testclass(){
        String requestInput = '';
        Blob requestBlob = Blob.valueOf(requestInput);
        Blob hash = Crypto.generateDigest('SHA-256', requestBlob);
        String requestSignature = EncodingUtil.base64encode(hash);
        system.debug('requestSignature: '+ requestSignature);
    }
}