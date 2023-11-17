interface ISiteMetadataResult {
  siteTitle: string;
  siteUrl: string;
  description: string;
  logo: string;
  navLinks: {
    name: string;
    url: string;
  }[];
}

const data: ISiteMetadataResult = {
  siteTitle: 'Running Page',
  siteUrl: 'https://lipeng.run',
  logo: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQTtc69JxHNcmN1ETpMUX4dozAgAN6iPjWalQ&usqp=CAU',
  description: 'My running history',
  navLinks: [
    {
      name: 'Blog',
      url: 'https://github.com/lipeng31',
    },
    {
      name: 'About',
      url: 'https://github.com/lipeng31',
    },
  ],
};

export default data;
